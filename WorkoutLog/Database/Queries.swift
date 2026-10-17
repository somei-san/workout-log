import Foundation
import GRDB

/// ホームのカード。種目と、最後の 1 回の記録の日時
struct ExerciseCard: Identifiable, Sendable, FetchableRecord {
    var exercise: Exercise
    var lastAt: Date?
    var lastUtcOffset: Int?

    var id: Int64? { exercise.id }

    init(row: Row) throws {
        exercise = try Exercise(row: row)
        lastAt = row["lastAt"]
        lastUtcOffset = row["lastUtcOffset"]
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

    static func fetchAll(_ db: Database) throws -> [ExerciseCard] {
        try ExerciseCard.fetchAll(db, sql: """
            SELECT exercise.*, r.performedAt AS lastAt, r.utcOffset AS lastUtcOffset
            FROM exercise
            LEFT JOIN record r ON r.id = (
                SELECT id FROM record WHERE exerciseId = exercise.id
                ORDER BY performedAt DESC, id DESC LIMIT 1)
            """)
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
