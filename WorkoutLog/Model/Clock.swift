import Foundation

/// 今の時刻。UI テストでは、起動引数「-uiTestingNow <ISO 8601 の日時>」で固定する。
/// 撮る日によって、画面の日付や経過日数が変わらないようにするため
enum Clock {
    static func now() -> Date {
        fixedNow ?? Date()
    }

    private static let fixedNow: Date? = UserDefaults.standard.string(forKey: "uiTestingNow")
        .flatMap { try? Date($0, strategy: .iso8601) }
}
