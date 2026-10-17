/// 記録の入力欄に出す強度の種類
enum IntensityKind: String, CaseIterable, Sendable {
    case none, rpe, rir

    var label: String {
        switch self {
        case .none: "非表示"
        case .rpe: "RPE"
        case .rir: "RIR"
        }
    }
}
