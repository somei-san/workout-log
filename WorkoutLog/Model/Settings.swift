import Foundation

/// UserDefaults のキー
enum SettingsKey {
    static let intensity = "intensity"
    static let historyColumns = "history.columns"
}

/// 記録の入力欄に出す強度の種類
enum IntensityKind: String, CaseIterable, Sendable {
    case none, rpe, rir

    static let initial = IntensityKind.rpe

    var label: String {
        switch self {
        case .none: "非表示"
        case .rpe: "RPE"
        case .rir: "RIR"
        }
    }
}

/// 種目の履歴の各行に出す項目。並び順は、行と見出しに出す順
enum HistoryColumn: String, CaseIterable, Sendable {
    case volume, estimated1RM, maxWeight, topSet, setCount

    var label: String {
        switch self {
        case .volume: "ボリューム"
        case .estimated1RM: "推定 1RM"
        case .maxWeight: "最大重量"
        case .topSet: "トップセット"
        case .setCount: "セット数"
        }
    }

    static let defaults: Set<HistoryColumn> = [.volume, .estimated1RM, .maxWeight]
    static let initialRaw = encode(defaults)

    /// UserDefaults に保存する形("volume,maxWeight")との変換
    static func decode(_ raw: String) -> Set<HistoryColumn> {
        let columns = Set(raw.split(separator: ",").compactMap { HistoryColumn(rawValue: String($0)) })
        return columns.isEmpty ? defaults : columns
    }

    static func encode(_ columns: Set<HistoryColumn>) -> String {
        allCases.filter(columns.contains).map(\.rawValue).joined(separator: ",")
    }

    func value(_ summary: RecordSummary) -> String {
        switch self {
        case .volume: Format.volume(summary.volume)
        case .estimated1RM: Format.decimal(summary.estimated1RM)
        case .maxWeight: Format.decimal(summary.maxWeight)
        case .topSet: summary.topSet.map { "\(Format.weight($0.weight))×\($0.reps)" } ?? "–"
        case .setCount: "\(summary.sets.count)"
        }
    }
}

/// ホームの並べ方
enum SortRule: String, CaseIterable, Sendable {
    case elapsedDesc, elapsedAsc, frequency4wDesc, frequency4wAsc, frequency3mDesc, frequency3mAsc

    var label: String {
        switch self {
        case .elapsedDesc: "経過日数：降順"
        case .elapsedAsc: "経過日数：昇順"
        case .frequency4wDesc: "頻度(4 週間)：降順"
        case .frequency4wAsc: "頻度(4 週間)：昇順"
        case .frequency3mDesc: "頻度(3 か月)：降順"
        case .frequency3mAsc: "頻度(3 か月)：昇順"
        }
    }

    var isDescending: Bool {
        switch self {
        case .elapsedDesc, .frequency4wDesc, .frequency3mDesc: true
        case .elapsedAsc, .frequency4wAsc, .frequency3mAsc: false
        }
    }

    var isElapsed: Bool {
        self == .elapsedDesc || self == .elapsedAsc
    }
}
