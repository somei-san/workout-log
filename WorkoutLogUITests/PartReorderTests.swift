import XCTest

/// ホームの部位の見方で、部位の名前を長押ししてドラッグし、部位の並びを変える
@MainActor
final class PartReorderTests: XCTestCase {
    let app = XCUIApplication()

    func testDragPartNameToEnd() {
        app.launchArguments = ["-home.mode", "part", "-uiTesting", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
            + XCUIApplication.exerciseArguments([("ベンチプレス", "chest"), ("デッドリフト", "back"), ("スクワット", "leg")])
        app.launchQuietly()
        let chest = app.staticTexts["胸"], leg = app.staticTexts["足"]
        XCTAssertTrue(chest.waitToAppear(timeout: 5), "部位ごとの見方で開かない")
        XCTAssertLessThan(chest.frame.minY, leg.frame.minY)

        // 長押しで帯に畳んだ後、帯の並びのいちばん下より下まで動かして離す
        let start = chest.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)

        // 離すと区切りの並びに戻り、胸がいちばん下に来る
        XCTAssertTrue(chest.waitToAppear(timeout: 3))
        XCTAssertGreaterThan(chest.frame.minY, leg.frame.minY, "胸が足の後ろに移らない")
        XCTAssertGreaterThan(chest.frame.minY, app.staticTexts["背中"].frame.minY)
    }
}
