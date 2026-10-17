import Foundation
import GRDB

/// 1 回の記録
struct WorkoutRecord: Codable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "record"

    var id: Int64?
    var exerciseId: Int64
    /// UTC で保存される
    var performedAt: Date
    /// 記録した場所の UTC との時差(分)
    var utcOffset: Int
    var memo: String

    init(id: Int64? = nil, exerciseId: Int64, performedAt: Date, timeZone: TimeZone = .current, memo: String = "") {
        self.id = id
        self.exerciseId = exerciseId
        self.performedAt = performedAt
        self.utcOffset = timeZone.secondsFromGMT(for: performedAt) / 60
        self.memo = memo
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension WorkoutRecord {
    /// 前回。同じ種目の記録を (performedAt, id) の順に並べた、1 つ前の記録。
    /// まだ保存していない記録(id が無い)では、同じ時刻の記録も前回に含める。後から作る記録のほうが id が大きいため
    func previous(_ db: Database) throws -> WorkoutRecord? {
        let at = Column("performedAt"), rowId = Column("id")
        let earlier = if let id { at < performedAt || (at == performedAt && rowId < id) } else { at <= performedAt }
        return try WorkoutRecord
            .filter(Column("exerciseId") == exerciseId)
            .filter(earlier)
            .order(at.desc, rowId.desc)
            .fetchOne(db)
    }
}
