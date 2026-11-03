import Foundation

/// 記録の入力欄に入れられる文字だけを残す
enum NumberInput {
    /// 数字と、最初の「.」1 つだけを残す
    static func decimal(_ text: String) -> String {
        var hasDot = false
        return halfwidth(text).filter { c in
            if c.isASCII, c.isNumber { return true }
            guard c == ".", !hasDot else { return false }
            hasDot = true
            return true
        }
    }

    /// 数字だけを残す
    static func integer(_ text: String) -> String {
        halfwidth(text).filter { $0.isASCII && $0.isNumber }
    }

    /// 全角の文字を半角にする。日本語入力のまま打った数字と「．」を、取り除かずに残すため
    private static func halfwidth(_ text: String) -> String {
        text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
    }
}
