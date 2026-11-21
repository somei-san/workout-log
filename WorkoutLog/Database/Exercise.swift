import GRDB

/// 部位。並び順（allCases）は、部位の並び（PartOrder）の初期値。保存した並びに無い部位も、この順で後ろに付く
enum Part: String, Codable, CaseIterable, Sendable {
    case chest, shoulder, back, arm, abs, leg, other

    var label: String {
        switch self {
        case .chest: "胸"
        case .shoulder: "肩"
        case .back: "背中"
        case .arm: "腕"
        case .abs: "腹"
        case .leg: "足"
        case .other: "その他"
        }
    }
}

/// 種目
struct Exercise: Codable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var part: Part
    var isHidden = false
    /// 最初に並べるセット数(0〜10)
    var initialRowCount = 0
    /// 種目の記録で、最後のセットからの経過時間を出すか。設定の「最後のセットからの経過時間」と両方がオンのときだけ出す
    var showsElapsed = true

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
