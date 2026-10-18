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
}
