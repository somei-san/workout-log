import GRDB

/// セット。重さと回数の入ったものだけを保存する
struct WorkoutSet: Codable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var recordId: Int64
    /// 記録の中の順番
    var position: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var rir: Int?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
