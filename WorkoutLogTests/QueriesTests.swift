import Foundation
import GRDB
import Testing
@testable import WorkoutLog

struct QueriesTests {
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.empty()
    }

    private func date(_ utc: String) throws -> Date {
        try Date(utc, strategy: .iso8601)
    }

    @Test func 頻度は記録した場所の日付で数える() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let cards = try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            // 今日を 2026-10-17(東京)とすると、4 週間は 2026-09-20 から
            for utc in [
                "2026-09-19T14:59:00Z", // 東京 09-19 23:59: 4 週間の外
                "2026-09-19T15:00:00Z", // 東京 09-20 00:00: 4 週間の内
                "2026-07-17T15:00:00Z", // 東京 07-18: 3 か月の内
                "2026-07-17T14:00:00Z", // 東京 07-17: 3 か月の外
            ] {
                var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: try date(utc), timeZone: tokyo)
                try record.insert(db)
            }
            let today = LocalDay(try date("2026-10-17T03:00:00Z"), timeZone: tokyo)
            return try ExerciseCard.fetchAll(db, today: today)
        }
        #expect(cards.first?.frequency4w == 1)
        #expect(cards.first?.frequency3m == 3)
    }

    @Test(arguments: [
        ("2026-10-17", 3, "2026-07-18"),
        ("2026-05-30", 3, "2026-03-01"),
        ("2026-12-30", 3, "2026-10-01"),
        ("2026-10-17", 1, "2026-09-18"),
    ])
    func 直近nか月はnか月前の翌日から(today: String, months: Int, start: String) throws {
        let day = LocalDay(try date(today + "T00:00:00Z"), timeZone: .gmt)
        #expect(day.start(ofLastMonths: months).sqlString == start)
    }

    @Test(arguments: [(1025.0, "1025"), (1312.5, "1312.5"), (1312.25, "1312.3"), (999.96, "1000")])
    func ボリュームは整数なら小数点を付けない(value: Double, text: String) {
        #expect(Format.volume(value) == text)
    }

    @Test func セットの並びは続けて並んだ同じ重さと回数のセットをセット数でまとめる_間に別のセットがあるか回数が違うときはまとめない() {
        func sets(_ values: [(Double, Int)]) -> [WorkoutSet] {
            values.enumerated().map { WorkoutSet(recordId: 0, position: $0.offset, weight: $0.element.0, reps: $0.element.1) }
        }
        #expect(Format.sets(sets([(102.5, 5), (102.5, 5), (100, 6), (100, 6), (97.5, 7)])) == "102.5kg×5×2 / 100kg×6×2 / 97.5kg×7")
        #expect(Format.sets(sets([(100, 6), (90, 8), (100, 6)])) == "100kg×6 / 90kg×8 / 100kg×6")
        #expect(Format.sets(sets([(100, 6), (100, 5)])) == "100kg×6 / 100kg×5")
        #expect(Format.sets([]) == "")
    }

    @Test func CSVは1セット1行で_カンマを含む値をダブルクォートで囲む() throws {
        let csv = try database.writer.write { db in
            var exercise = Exercise(name: "ベンチプレス", part: .chest)
            try exercise.insert(db)
            var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: try date("2026-10-17T00:12:00Z"),
                                       timeZone: TimeZone(identifier: "Asia/Tokyo")!, memo: "狭め, 止める")
            try record.insert(db)
            var first = WorkoutSet(recordId: record.id!, position: 0, weight: 100, reps: 5, rpe: 8)
            try first.insert(db)
            var second = WorkoutSet(recordId: record.id!, position: 1, weight: 97.5, reps: 6)
            try second.insert(db)
            return try CSVExport.make(db)
        }
        #expect(csv == """
            種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ\r
            ベンチプレス,胸,2026/10/17,09:12,1,100,5,8,,"狭め, 止める"\r
            ベンチプレス,胸,2026/10/17,09:12,2,97.5,6,,,"狭め, 止める"\r

            """)
    }

    @Test func CSVは記録を日付と時刻の順に並べ_ダブルクォートと改行を含む値も囲む() throws {
        let csv = try database.writer.write { db in
            let tokyo = TimeZone(identifier: "Asia/Tokyo")!
            var squat = Exercise(name: "スクワット", part: .leg)
            try squat.insert(db)
            var bench = Exercise(name: "ベンチ\"ワイド\"", part: .chest)
            try bench.insert(db)
            var later = WorkoutRecord(exerciseId: squat.id!, performedAt: try date("2026-10-18T00:00:00Z"), timeZone: tokyo)
            try later.insert(db)
            var laterSet = WorkoutSet(recordId: later.id!, position: 0, weight: 140, reps: 3, rir: 1)
            try laterSet.insert(db)
            var earlier = WorkoutRecord(exerciseId: bench.id!, performedAt: try date("2026-10-17T00:00:00Z"), timeZone: tokyo, memo: "1行目\n2行目")
            try earlier.insert(db)
            var earlierSet = WorkoutSet(recordId: earlier.id!, position: 0, weight: 100, reps: 5)
            try earlierSet.insert(db)
            return try CSVExport.make(db)
        }
        #expect(csv == [
            "種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ",
            "\"ベンチ\"\"ワイド\"\"\",胸,2026/10/17,09:00,1,100,5,,,\"1行目\n2行目\"",
            "スクワット,足,2026/10/18,09:00,1,140,3,,1,",
        ].map { $0 + "\r\n" }.joined())
    }

    @Test func 記録が無ければCSVは見出しの行だけ() throws {
        let csv = try database.reader.read(CSVExport.make)
        #expect(csv == "種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ\r\n")
    }
}
