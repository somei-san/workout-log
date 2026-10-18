import Foundation

extension WorkoutSet {
    /// 推定 1RM(Brzycki 式)。式は 37 回以上で割る数が 0 以下になるので、そのときは重さをそのまま使う
    var estimated1RM: Double {
        reps < 37 ? weight * 36 / Double(37 - reps) : weight
    }
}

/// 1 回の記録と、そのセットから計算する値
struct RecordSummary: Identifiable, Sendable {
    var record: WorkoutRecord
    var sets: [WorkoutSet]

    var id: Int64? { record.id }
    var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var estimated1RM: Double? { sets.map(\.estimated1RM).max() }
    var maxWeight: Double? { sets.map(\.weight).max() }
    /// 最も重いセット。同じ重さなら回数の多いほう
    var topSet: WorkoutSet? { sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) } }
}

enum Format {
    /// 重さ。整数なら小数点を付けない(135、132.5)
    static func weight(_ value: Double) -> String {
        String(format: "%g", value)
    }

    /// 種目の履歴の値。小数 1 桁(1300.0)
    static func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "–"
    }

    /// ボリューム。小数 1 桁で、整数なら小数点を付けない(1300、1312.5)
    static func volume(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
    }

    static func sets(_ sets: [WorkoutSet]) -> String {
        sets.map { "\(weight($0.weight))kg×\($0.reps)" }.joined(separator: " / ")
    }

    static func date(_ date: Date, timeZone: TimeZone, weekday: Bool = false, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd" + (weekday ? "(EEE)" : "") + (time ? " HH:mm" : "")
        return formatter.string(from: date)
    }
}
