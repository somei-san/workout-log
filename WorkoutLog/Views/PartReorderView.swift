import SwiftUI

/// ホームの部位の見方で、部位を並べ替えている間の状態
struct PartReorder {
    struct Band: Identifiable {
        let part: Part
        let names: [String]
        var id: Part { part }
    }

    /// 並べ替えを始めたときに画面に出ていた部位の帯。上からの順
    let bands: [Band]
    /// 持っている部位
    let held: Part
    /// 持っている部位の、並べ替えを始めたときの位置
    let start: Int
    /// 持っている部位を今離すと入る位置
    var target: Int
    /// 並べ替えを始めてから指が縦に動いた量
    var moved: CGFloat = 0
    /// 帯 1 本の高さと、帯の間の隙間
    let bandHeight: CGFloat
    static let spacing: CGFloat = 6

    init(bands: [Band], held: Part, start: Int, bandHeight: CGFloat) {
        self.bands = bands
        self.held = held
        self.start = start
        self.target = start
        self.bandHeight = bandHeight
    }

    var pitch: CGFloat { bandHeight + Self.spacing }

    /// 持っている帯の上端の位置。帯は畳んだ位置から、指が動いた分だけ動かす。
    /// 指の位置そのものに合わせると、畳む前の名前の位置にいた指と、畳んだ後の帯の位置がずれるため
    var heldY: CGFloat { CGFloat(start) * pitch + moved }

    /// 今離したときの部位の並び
    var order: [Part] {
        bands.map(\.part).filter { $0 != held }.inserting(held, at: target)
    }

    /// 指が縦に moved だけ動いたときに入る位置。帯の半分を超えて動いたら、隣の位置にする
    func target(moved: CGFloat) -> Int {
        let slot = start + Int((moved / pitch).rounded())
        return min(max(slot, 0), bands.count - 1)
    }
}

/// 部位を並べ替えている間、透明にした一覧の上に重ねて出す部位の帯の並び。
/// 持っている部位の帯は指に付いて動き、ほかの帯は避けて場所を空ける
struct PartReorderView: View {
    let reorder: PartReorder

    var body: some View {
        let others = reorder.bands.filter { $0.part != reorder.held }
        ZStack(alignment: .top) {
            ForEach(others.indices, id: \.self) { i in
                let slot = i < reorder.target ? i : i + 1
                PartBand(band: others[i], height: reorder.bandHeight)
                    .offset(y: CGFloat(slot) * reorder.pitch)
            }
            if let held = reorder.bands.first(where: { $0.part == reorder.held }) {
                PartBand(band: held, height: reorder.bandHeight, isHeld: true)
                    .offset(y: reorder.heldY)
                    // 指に付いて動かすので、並びが変わったときのアニメーションを掛けない
                    .transaction { $0.animation = nil }
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 並べ替えは部位の名前の操作（前へ移動・後ろへ移動）で読み上げるので、帯は読み上げない
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

/// 部位の帯。部位のアイコン、部位の名前、種目の数と種目名を 1 行に出す
private struct PartBand: View {
    let band: PartReorder.Band
    let height: CGFloat
    var isHeld = false

    var body: some View {
        HStack(spacing: 8) {
            PartIcon(part: band.part)
            Text(band.part.label).font(.subheadline.bold())
            Text("\(band.names.count)").font(.caption).foregroundStyle(.secondary)
            Text(band.names.joined(separator: "・"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
        }
        .lineLimit(1)
        // 帯の高さに上限があるので、文字を大きくしたときは帯に収まるまで縮める
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Color(isHeld ? .tertiarySystemBackground : .secondarySystemBackground), in: .rect(cornerRadius: 10))
        .scaleEffect(isHeld ? 1.04 : 1)
        .shadow(color: .black.opacity(isHeld ? 0.35 : 0), radius: 12, y: 6)
    }
}

extension Array where Element: Equatable {
    func inserting(_ element: Element, at index: Int) -> [Element] {
        var array = self
        array.insert(element, at: Swift.min(index, array.count))
        return array
    }

    /// from の要素を to の位置に移した配列
    func moving(from: Int, to: Int) -> [Element] {
        var array = self
        let element = array.remove(at: from)
        array.insert(element, at: to)
        return array
    }
}
