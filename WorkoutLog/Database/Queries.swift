import Foundation
import GRDB

/// ホームのカード。種目と、最後の 1 回の記録の日時と、頻度
struct ExerciseCard: Identifiable, Sendable, FetchableRecord {
    var exercise: Exercise
    var lastAt: Date?
    var lastUtcOffset: Int?
    /// 直近 4 週間の 1 回の記録の数
    var frequency4w: Int
    /// 直近 3 か月の 1 回の記録の数
    var frequency3m: Int

    var id: Int64? { exercise.id }

    init(row: Row) throws {
        exercise = try Exercise(row: row)
        lastAt = row["lastAt"]
        lastUtcOffset = row["lastUtcOffset"]
        frequency4w = row["frequency4w"]
        frequency3m = row["frequency3m"]
    }

    func frequency(_ rule: SortRule) -> Int {
        switch rule {
        case .frequency3mDesc, .frequency3mAsc: frequency3m
        default: frequency4w
        }
    }

    /// 最後に実施した日(記録した場所の時刻で数える)
    var lastDay: LocalDay? {
        guard let lastAt, let lastUtcOffset else { return nil }
        return LocalDay(performedAt: lastAt, utcOffset: lastUtcOffset)
    }

    /// 経過日数。未実施なら nil。
    /// 時差の大きい場所で開くと、最後の記録の日付が今日より後になることがあるので、0 で止める
    func elapsedDays(today: LocalDay) -> Int? {
        lastDay.map { max(0, $0.days(to: today)) }
    }

    /// 頻度は、記録した場所の日付で数える。4 週間は今日を含む 28 日、3 か月は 3 か月前の翌日から今日まで
    static func fetchAll(_ db: Database, today: LocalDay) throws -> [ExerciseCard] {
        let since4w = today.adding(days: -27).sqlString
        let since3m = today.start(ofLastMonths: 3).sqlString
        // performedAt は UTC なので、utcOffset を足してから日付を切り出す
        let localDay = "date(performedAt, utcOffset || ' minutes')"
        return try ExerciseCard.fetchAll(db, sql: """
            SELECT exercise.*, r.performedAt AS lastAt, r.utcOffset AS lastUtcOffset,
                (SELECT COUNT(*) FROM record WHERE exerciseId = exercise.id AND \(localDay) >= ?) AS frequency4w,
                (SELECT COUNT(*) FROM record WHERE exerciseId = exercise.id AND \(localDay) >= ?) AS frequency3m
            FROM exercise
            LEFT JOIN record r ON r.id = (
                SELECT id FROM record WHERE exerciseId = exercise.id
                ORDER BY performedAt DESC, id DESC LIMIT 1)
            """, arguments: [since4w, since3m])
    }
}

extension RecordSummary {
    /// 種目の 1 回の記録を、新しい順に
    static func fetchAll(_ db: Database, exerciseId: Int64) throws -> [RecordSummary] {
        let records = try WorkoutRecord
            .filter(Column("exerciseId") == exerciseId)
            .order(Column("performedAt").desc, Column("id").desc)
            .fetchAll(db)
        let sets = try WorkoutSet
            .filter(records.compactMap(\.id).contains(Column("recordId")))
            .order(Column("position"))
            .fetchAll(db)
        let setsByRecord = Dictionary(grouping: sets, by: \.recordId)
        return records.map { RecordSummary(record: $0, sets: setsByRecord[$0.id!] ?? []) }
    }
}

extension WorkoutRecord {
    func fetchSets(_ db: Database) throws -> [WorkoutSet] {
        guard let id else { return [] }
        return try WorkoutSet.filter(Column("recordId") == id).order(Column("position")).fetchAll(db)
    }

    func sharesDay(_ db: Database) throws -> Bool {
        sharesDay(with: try WorkoutRecord.filter(Column("exerciseId") == exerciseId).fetchAll(db))
    }
}
