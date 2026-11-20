import Foundation

/// UserDefaults のキー
enum SettingsKey {
    static let intensity = "intensity"
    static let historyColumns = "history.columns"
    static let appearance = "appearance"
    static let partOrder = "partOrder"
}

/// 部位の並び。ホームの部位の見方の区切りと、種目の追加・設定の部位のボタンが、この順を使う
enum PartOrder {
    /// UserDefaults に保存する形("leg,chest,...")から読む。
    /// 保存した中に無い部位（部位を足したときなど）は、Part の順で後ろに付ける
    static func decode(_ raw: String) -> [Part] {
        var order: [Part] = []
        for part in raw.split(separator: ",").compactMap({ Part(rawValue: String($0)) }) where !order.contains(part) {
            order.append(part)
        }
        return order + Part.allCases.filter { !order.contains($0) }
    }

    static func encode(_ order: [Part]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// order のうち visible に入っている部位を、visible の順に並べ直した並び。
    /// 画面に出ていない部位（種目の無い部位）は、同じ位置に残す
    static func applying(_ visible: [Part], to order: [Part]) -> [Part] {
        var rest = visible[...]
        return order.map { part in
            guard visible.contains(part), let next = rest.popFirst() else { return part }
            return next
        }
    }
}

/// アプリの外観
enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark

    static let initial = Appearance.dark

    var label: String {
        switch self {
        case .system: "端末に合わせる"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }
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

    /// column の表示と非表示を切り替えた後の表示項目。最後の 1 つは非表示にできないので、すべて非表示になるなら nil
    static func toggled(_ columns: Set<HistoryColumn>, _ column: HistoryColumn, isOn: Bool) -> Set<HistoryColumn>? {
        var columns = columns
        if isOn { columns.insert(column) } else { columns.remove(column) }
        return columns.isEmpty ? nil : columns
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
