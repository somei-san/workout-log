// アプリのアイコンと部位の形を CoreGraphics で描き、Assets.xcassets に書き出す。
// 実行: swift scripts/make-icons.swift [見本の PNG の出力先]
// 見本の出力先を渡すと、部位のアイコン(ライトとダーク)と App アイコンを並べた PNG も書く。
// 部位の色は WorkoutLog/Views/Common.swift の Part.color と同じ値にする(見本の描画にだけ使う)。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("WorkoutLog/Assets.xcassets")

func rgb(_ hex: Int, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// MARK: - SVG のパスの読み込み

/// SVG のパスのうち、絶対座標の M L H V C Q Z だけを読む
func svgPath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var tokens: [String] = []
    var number = ""
    for ch in d {
        if ch.isLetter {
            if !number.isEmpty { tokens.append(number); number = "" }
            tokens.append(String(ch))
        } else if ch == " " || ch == "," {
            if !number.isEmpty { tokens.append(number); number = "" }
        } else if ch == "-" && !number.isEmpty {
            tokens.append(number); number = "-"
        } else {
            number.append(ch)
        }
    }
    if !number.isEmpty { tokens.append(number) }

    var i = 0
    var command = ""
    func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
        let current = path.isEmpty ? .zero : path.currentPoint
        switch command {
        case "M": path.move(to: CGPoint(x: next(), y: next())); command = "L"
        case "L": path.addLine(to: CGPoint(x: next(), y: next()))
        case "H": path.addLine(to: CGPoint(x: next(), y: current.y))
        case "V": path.addLine(to: CGPoint(x: current.x, y: next()))
        case "C":
            let c1 = CGPoint(x: next(), y: next()), c2 = CGPoint(x: next(), y: next())
            path.addCurve(to: CGPoint(x: next(), y: next()), control1: c1, control2: c2)
        case "Q":
            let c = CGPoint(x: next(), y: next())
            path.addQuadCurve(to: CGPoint(x: next(), y: next()), control: c)
        case "Z": path.closeSubpath()
        default: fatalError("読めないパスのコマンド: \(command)")
        }
    }
    return path
}

func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: - 体(100×100、左上が原点)

/// 体の部品。part が nil の部品は、どの部位でも薄い色で描く
struct Piece {
    let part: String?
    let path: CGPath
}

/// 左半分を描き、右半分は鏡に映して足す
func body(center: [Piece], half: [Piece]) -> [Piece] {
    var mirror = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1)
    return center + half + half.map { Piece(part: $0.part, path: $0.path.copy(using: &mirror)!) }
}

let head = Piece(part: nil, path: svgPath("M50 3 C56 3 59 8 59 14 C59 21 55 25 50 25 C45 25 41 21 41 14 C41 8 44 3 50 3 Z"))
let deltoid = "M28 31 C19 32 13 38 13 47 C13 51 14 54 16 56 C19 48 23 42 31 37 C31 34 30 32 28 31 Z"
let upperArm = "M16 59 C18 51 22 45 29 42 C31 50 29 60 26 67 C22 70 17 68 16 63 Z"
let forearm = "M15 70 C18 70 22 71 25 71 C25 80 22 88 19 95 L12 95 C11 86 12 77 15 70 Z"

/// 前から見た上半身
let frontBody = body(center: [head], half: [
    Piece(part: nil, path: svgPath("M44 24 C43 28 37 30 29 31 L49 33 L49 26 Z")), // 僧帽筋
    Piece(part: "shoulder", path: svgPath(deltoid)),
    Piece(part: "chest", path: svgPath("M32 36 C37 33 44 33 49 34 L49 51 C44 55 37 55 32 52 C29 48 29 40 32 36 Z")),
    Piece(part: "arm", path: svgPath(upperArm)),
    Piece(part: "arm", path: svgPath(forearm)),
    Piece(part: "abs", path: roundRect(41.5, 56, 7.5, 8.5, 2.5)),
    Piece(part: "abs", path: roundRect(41.5, 66.5, 7.5, 8.5, 2.5)),
    Piece(part: "abs", path: roundRect(41.5, 77, 7.5, 9, 2.5)),
    Piece(part: "abs", path: svgPath("M32 55 C35 57 37 57 39.5 57 L39.5 88 C36 86 34 81 33.5 76 C32.5 69 32 61 32 55 Z")), // 腹斜筋
])

/// 後ろから見た上半身
let backBody = body(center: [head], half: [
    Piece(part: "back", path: svgPath("M49 25 C46 28 37 30 29 31 C37 33 44 38 49 50 Z")), // 僧帽筋
    Piece(part: nil, path: svgPath(deltoid)),
    Piece(part: "back", path: svgPath("M32 38 C39 42 45 49 49 56 L49 78 C44 75 38 69 35 62 C32 55 30 45 32 38 Z")), // 広背筋
    Piece(part: nil, path: svgPath("M40 76 C43 78 46 80 49 81 L49 92 L39 92 C39 86 39 81 40 76 Z")), // 脊柱起立筋
    Piece(part: nil, path: svgPath(upperArm)),
    Piece(part: nil, path: svgPath(forearm)),
])

/// 前から見た脚
let legsBody = body(center: [], half: [
    Piece(part: nil, path: svgPath("M26 3 L49 3 L49 9 C44 8 34 8 27 10 Z")), // 腰
    Piece(part: "leg", path: svgPath("M27 13 C34 10 44 11 49 14 C48 27 46 39 44 50 C40 54 34 54 31 50 C27 38 25 24 27 13 Z")), // 太もも
    Piece(part: nil, path: svgPath("M32 54 C35 56 40 56 43 54 L43 58 C40 60 35 60 32 58 Z")), // 膝
    Piece(part: "leg", path: svgPath("M31 61 C35 59 40 59 43 61 C45 72 43 83 41 93 L34 93 C31 82 29 71 31 61 Z")), // すね・ふくらはぎ
    Piece(part: nil, path: svgPath("M33 95 L42 95 L45 99 L31 99 Z")), // 足先
])

let dumbbell: [CGPath] = [
    roundRect(22, 44, 56, 12, 3), roundRect(14, 22, 15, 56, 6), roundRect(71, 22, 15, 56, 6),
    roundRect(3, 33, 13, 34, 5), roundRect(84, 33, 13, 34, 5),
]

/// 部位のアイコンの 2 枚の層。base は体の残り(薄い色)、target は鍛える部位(濃い色)。
/// どちらも 100×100 を部位の色の丸の大きさとして、丸の中に収まる位置に置く
struct PartLayers {
    let name: String
    let color: Int
    let base: [CGPath]
    let target: [CGPath]
}

func layers(_ name: String, color: Int, body pieces: [Piece]) -> PartLayers {
    // 頭や足先が丸の縁に掛からないよう、一回り小さくして中央に置く
    var t = CGAffineTransform(translationX: 10, y: 10).scaledBy(x: 0.8, y: 0.8)
    let placed = pieces.map { Piece(part: $0.part, path: $0.path.copy(using: &t)!) }
    return PartLayers(name: name, color: color,
                      base: placed.filter { $0.part != name }.map(\.path),
                      target: placed.filter { $0.part == name }.map(\.path))
}

let partLayers: [PartLayers] = [
    layers("chest", color: 0xd9b13b, body: frontBody),
    layers("shoulder", color: 0x9b6dd6, body: frontBody),
    layers("back", color: 0xb87333, body: backBody),
    layers("arm", color: 0xc8445a, body: frontBody),
    layers("abs", color: 0x4caf7a, body: frontBody),
    layers("leg", color: 0x6ab0e0, body: legsBody),
    // その他は体にせず、ダンベルにする。横に長く両端が丸の縁に掛かるので、体より小さくする
    {
        var t = CGAffineTransform(translationX: 20, y: 20).scaledBy(x: 0.6, y: 0.6)
        return PartLayers(name: "other", color: 0x8e8e96, base: [], target: dumbbell.map { $0.copy(using: &t)! })
    }(),
]

/// 左上を原点、100×100 の座標で描けるようにしてから形を塗る
func fill(_ paths: [CGPath], in ctx: CGContext, rect: CGRect, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: rect.width / 100, y: -rect.height / 100)
    ctx.setFillColor(color)
    // 鏡に映した部品は輪郭の向きが逆になり、重なりが穴になるので、1 つの形に合わせてから塗る
    if let first = paths.first {
        ctx.addPath(paths.dropFirst().reduce(first) { $0.union($1) })
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// MARK: - 書き出し

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

/// 形を、テンプレート画像として使うベクターの PDF の imageset に書く
func writeTemplateImage(_ paths: [CGPath], name: String) throws {
    let dir = assets.appendingPathComponent("Part/\(name).imageset")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    let ctx = CGContext(dir.appendingPathComponent("\(name).pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    fill(paths, in: ctx, rect: box, color: rgb(0x000000))
    ctx.endPDFPage()
    ctx.closePDF()
    try writeJSON([
        "images": [["filename": "\(name).pdf", "idiom": "universal"]],
        "info": ["author": "xcode", "version": 1],
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ], to: dir.appendingPathComponent("Contents.json"))
}

func bitmap(width: Int, height: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}

/// App アイコン。黒の斜めのグラデーションに、斜めに置いたライムのダンベル
func drawAppIcon(in ctx: CGContext, size: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0x2a2d33), rgb(0x0e0f12)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    // 左下から右上へ上がる向き。CoreGraphics は y が上向きなので、左回りに 35°
    ctx.rotate(by: 35 * .pi / 180)
    ctx.translateBy(x: -size / 2, y: -size / 2)
    fill(dumbbell, in: ctx, rect: CGRect(x: size * 0.12, y: size * 0.12, width: size * 0.76, height: size * 0.76),
         color: rgb(0xc8f23c))
    ctx.restoreGState()
}

func writeAppIcon() throws {
    let ctx = bitmap(width: 1024, height: 1024, opaque: true)
    drawAppIcon(in: ctx, size: 1024)
    let dir = assets.appendingPathComponent("AppIcon.appiconset")
    try writePNG(ctx.makeImage()!, to: dir.appendingPathComponent("AppIcon.png"))
    try writeJSON([
        "images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
        "info": ["author": "xcode", "version": 1],
    ], to: dir.appendingPathComponent("Contents.json"))
}

/// 見本。上の段がライト、下の段がダークの背景に置いた部位のアイコン。右端が App アイコン
func writePreview(to url: URL) throws {
    let large: CGFloat = 160, gap: CGFloat = 24, appSize: CGFloat = 340
    let width = Int(CGFloat(partLayers.count) * (large + gap) + gap * 2 + appSize)
    let height = Int(gap * 3 + large * 2 + gap * 2)
    let ctx = bitmap(width: width, height: height, opaque: true)
    ctx.setFillColor(rgb(0xffffff))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(rgb(0x1c1c1e))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width) - appSize - gap, height: large + gap * 2.5))
    for (i, layer) in partLayers.enumerated() {
        let x = gap + CGFloat(i) * (large + gap)
        // (y, 丸の濃さ, 体の濃さ)。Common.swift の PartIcon と同じ値
        for (y, circle, base) in [(CGFloat(height) - gap - large, 0.18, 0.45), (gap * 1.2, 0.28, 0.55)] {
            let rect = CGRect(x: x, y: y, width: large, height: large)
            ctx.setFillColor(rgb(layer.color, alpha: circle))
            ctx.fillEllipse(in: rect)
            fill(layer.base, in: ctx, rect: rect, color: rgb(layer.color, alpha: base))
            fill(layer.target, in: ctx, rect: rect, color: rgb(layer.color))
        }
    }
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(width) - appSize - gap, y: (CGFloat(height) - appSize) / 2)
    ctx.addPath(roundRect(0, 0, appSize, appSize, appSize * 0.225))
    ctx.clip()
    drawAppIcon(in: ctx, size: appSize)
    ctx.restoreGState()
    try writePNG(ctx.makeImage()!, to: url)
}

try writeJSON(["info": ["author": "xcode", "version": 1]], to: assets.appendingPathComponent("Contents.json"))
try writeAppIcon()
// 形を消したり名前を変えたりしたときに古い画像が残らないよう、部位の画像はフォルダーごと書き直す
let partDir = assets.appendingPathComponent("Part")
if FileManager.default.fileExists(atPath: partDir.path) {
    try FileManager.default.removeItem(at: partDir)
}
// 体の残りが無い部位(その他)にも空の画像を書き、画面の側がどの部位も同じ 2 枚を重ねられるようにする
for layer in partLayers {
    try writeTemplateImage(layer.base, name: "\(layer.name)-base")
    try writeTemplateImage(layer.target, name: "\(layer.name)-target")
}
try writeJSON(["info": ["author": "xcode", "version": 1], "properties": ["provides-namespace": true]],
              to: assets.appendingPathComponent("Part/Contents.json"))
if CommandLine.arguments.count > 1 {
    try writePreview(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
