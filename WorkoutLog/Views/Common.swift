import SwiftUI

extension EnvironmentValues {
    @Entry var appDatabase: AppDatabase = .shared
}

extension Part {
    /// 値は scripts/make-icons.swift が持ち、アセットカタログに書き出している
    var color: Color { Color("Part/\(rawValue)") }
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
