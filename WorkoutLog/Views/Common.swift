import SwiftUI

extension EnvironmentValues {
    @Entry var appDatabase: AppDatabase = .shared
}

extension Part {
    /// scripts/make-icons.swift も、アイコンの見本を描くために同じ値を持つ
    var color: Color {
        switch self {
        case .chest: Color(red: 0xd9 / 255, green: 0xb1 / 255, blue: 0x3b / 255)
        case .shoulder: Color(red: 0x9b / 255, green: 0x6d / 255, blue: 0xd6 / 255)
        case .back: Color(red: 0xb8 / 255, green: 0x73 / 255, blue: 0x33 / 255)
        case .arm: Color(red: 0xc8 / 255, green: 0x44 / 255, blue: 0x5a / 255)
        case .abs: Color(red: 0x4c / 255, green: 0xaf / 255, blue: 0x7a / 255)
        case .leg: Color(red: 0x6a / 255, green: 0xb0 / 255, blue: 0xe0 / 255)
        case .other: Color(red: 0x8e / 255, green: 0x8e / 255, blue: 0x96 / 255)
        }
    }
}

/// 部位のアイコン。部位の色の薄い丸に、体を薄い色で、そのうち鍛える部位を濃い色で重ねる。
/// 画像は scripts/make-icons.swift で描いて書き出している
struct PartIcon: View {
    let part: Part
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // ダークでは背景が暗く、薄い色が沈むので、丸と体を濃くする。
        // scripts/make-icons.swift の見本も同じ値で描いている
        let dark = colorScheme == .dark
        // テンプレート画像 1 枚には 1 色しか付けられないので、体の残りと鍛える部位を別の画像にして重ねる
        ZStack {
            Circle().fill(part.color.opacity(dark ? 0.28 : 0.18))
            layer("base").foregroundStyle(part.color.opacity(dark ? 0.55 : 0.45))
            layer("target").foregroundStyle(part.color)
        }
        .frame(width: 22, height: 22)
        .accessibilityElement()
        .accessibilityLabel(part.label)
    }

    private func layer(_ name: String) -> some View {
        Image("Part/\(part.rawValue)-\(name)").resizable()
    }
}

/// 画面の移動先
enum Route: Hashable {
    case history(exerciseId: Int64)
    case record(recordId: Int64)
    /// 新しい 1 回の記録。「＋」を押すたびに別の画面にするため token を持つ
    case newRecord(exerciseId: Int64, token: UUID)
    case analysis(exerciseId: Int64)
    case settings
}
