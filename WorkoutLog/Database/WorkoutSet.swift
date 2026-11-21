import Foundation
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
    /// 重さと回数がそろってセットになった時刻。後から値を直しても変えない。直した時刻は、入れた時刻ではないため。
    /// 入れた時刻が分からないセット（古いデータベースから移したセット、CSV から読み込んだセット）は nil
    var createdAt: Date?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
