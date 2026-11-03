import Foundation
import GRDB
import Testing
@testable import WorkoutLog

struct HomeOrderTests {
    let database: AppDatabase
    /// 東京の 2026-10-17
    let today: LocalDay

    init() throws {
        database = try AppDatabase.empty()
        today = LocalDay(try Date("2026-10-17T03:00:00Z", strategy: .iso8601), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    }

    /// 種目を足し、今日から daysAgo 日前の東京の正午に 1 回の記録を作って、ホームのカードを返す
    private func cards(_ exercises: [(name: String, part: Part, daysAgo: [Int])]) throws -> [ExerciseCard] {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let noon = try Date("2026-10-17T03:00:00Z", strategy: .iso8601)
        return try database.writer.write { db in
            for item in exercises {
                var exercise = Exercise(name: item.name, part: item.part)
                try exercise.insert(db)
                for days in item.daysAgo {
                    var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: noon.addingTimeInterval(TimeInterval(-days * 86400)), timeZone: tokyo)
                    try record.insert(db)
                }
            }
            return try ExerciseCard.fetchAll(db, today: today)
        }
    }

    private func sample() throws -> [ExerciseCard] {
        try cards([
            ("ベンチプレス", .chest, [2, 5, 9]), // 経過日数 2、4 週間の頻度 3、3 か月の頻度 3
            ("スクワット", .leg, [7, 40, 50, 60, 70]), // 7、1、5
            ("デッドリフト", .back, []), // 未実施
            ("アームカール", .arm, [7]), // 7、1、1
        ])
    }

    private func names(_ rule: SortRule, _ cards: [ExerciseCard]) -> [String] {
        rule.sorted(cards, today: today).map(\.exercise.name)
    }

    @Test func 経過日数の降順は長く空いた種目が先頭で_未実施はいちばん大きいとして扱う() throws {
        #expect(names(.elapsedDesc, try sample()) == ["デッドリフト", "アームカール", "スクワット", "ベンチプレス"])
    }

    @Test func 経過日数の昇順は最近した種目が先頭で_未実施は最後() throws {
        #expect(names(.elapsedAsc, try sample()) == ["ベンチプレス", "アームカール", "スクワット", "デッドリフト"])
    }

    @Test func 頻度は選んだ期間の1回の記録の数で並べ_未実施は0として扱う() throws {
        let cards = try sample()
        #expect(names(.frequency4wDesc, cards) == ["ベンチプレス", "アームカール", "スクワット", "デッドリフト"])
        #expect(names(.frequency4wAsc, cards) == ["デッドリフト", "アームカール", "スクワット", "ベンチプレス"])
        #expect(names(.frequency3mDesc, cards) == ["スクワット", "ベンチプレス", "アームカール", "デッドリフト"])
        #expect(names(.frequency3mAsc, cards) == ["デッドリフト", "アームカール", "ベンチプレス", "スクワット"])
    }

    @Test func 頻度が同じ種目は降順でも昇順でも経過日数が大きい順() throws {
        // 名前の順とは逆になるようにする
        let cards = try cards([("アームカール", .arm, [1]), ("スクワット", .leg, [10])])
        #expect(names(.frequency4wDesc, cards) == ["スクワット", "アームカール"])
        #expect(names(.frequency4wAsc, cards) == ["スクワット", "アームカール"])
    }

    @Test func 部位の見方で経過日数を選ぶと区切りは胸_肩_背中_腕_腹_足_その他の順() throws {
        let order: [Part] = [.chest, .shoulder, .back, .arm, .abs, .leg, .other]
        #expect(SortRule.elapsedDesc.partOrder(try sample()) == order)
        #expect(SortRule.elapsedAsc.partOrder(try sample()) == order)
        #expect(order.map(\.label) == ["胸", "肩", "背中", "腕", "腹", "足", "その他"])
    }

    @Test func 部位の見方で頻度を選ぶと区切りは部位の頻度の合計で並べ_合計が同じなら胸から順() throws {
        let cards = try sample()
        #expect(SortRule.frequency3mDesc.partOrder(cards) == [.leg, .chest, .arm, .shoulder, .back, .abs, .other])
        #expect(SortRule.frequency3mAsc.partOrder(cards) == [.shoulder, .back, .abs, .other, .arm, .chest, .leg])
    }

    @Test func 部位の頻度の合計に非表示の種目は含めない() throws {
        // 足の合計は、非表示のレッグプレスを含めると 4 で胸の 3 より多いが、含めなければ 1
        var cards = try cards([("ベンチプレス", .chest, [1, 2, 3]), ("スクワット", .leg, [1]), ("レッグプレス", .leg, [1, 2, 3])])
        #expect(SortRule.frequency4wDesc.partOrder(cards).prefix(2) == [.leg, .chest])
        let i = try #require(cards.firstIndex { $0.exercise.name == "レッグプレス" })
        cards[i].exercise.isHidden = true
        #expect(SortRule.frequency4wDesc.partOrder(cards).prefix(2) == [.chest, .leg])
    }

    @Test func カードは最後の1回の記録の日付を記録した場所の時刻で出す() throws {
        let card = try database.writer.write { db in
            var exercise = Exercise(name: "ベンチプレス", part: .chest)
            try exercise.insert(db)
            // 東京の 2026-10-17 07:30。UTC では前日
            var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: try Date("2026-10-16T22:30:00Z", strategy: .iso8601),
                                       timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            try record.insert(db)
            var older = WorkoutRecord(exerciseId: exercise.id!, performedAt: try Date("2026-10-10T03:00:00Z", strategy: .iso8601),
                                      timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            try older.insert(db)
            return try ExerciseCard.fetchAll(db, today: today).first!
        }
        #expect(card.lastDay == today)
        #expect(card.elapsedDays(today: today) == 0)
    }

    @Test func 未実施の種目は経過日数が無い() throws {
        let card = try #require(try cards([("デッドリフト", .back, [])]).first)
        #expect(card.lastDay == nil)
        #expect(card.elapsedDays(today: today) == nil)
    }

    @Test func 最後の記録の日付が今日より後でも経過日数は0() throws {
        let card = try #require(try cards([("ベンチプレス", .chest, [-1])]).first)
        #expect(card.elapsedDays(today: today) == 0)
    }
}
