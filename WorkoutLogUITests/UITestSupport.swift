import XCTest

@MainActor
extension XCUIApplication {
    /// 空のデータベースと空の設定で起動する
    func launchEmpty() {
        launchArguments = ["-uiTesting"]
        launch()
    }

    /// ホームの「＋」から種目を足す。名前が空の間は「追加」を押せないことも確かめる
    func addExercise(_ name: String, part: String) {
        buttons["種目を追加"].tap()
        let add = buttons["追加"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled, "名前が空なのに「追加」を押せる")
        let field = textFields["例: ベンチプレス"]
        field.tap()
        // 起動直後のシミュレーターは、キーボードが出るまでに時間がかかる
        _ = keyboards.firstMatch.waitForExistence(timeout: 10)
        field.typeText(name)
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch.tap()
        XCTAssertTrue(add.isEnabled)
        add.tap()
    }

    /// ホームの種目のカード
    func card(_ name: String) -> XCUIElement {
        buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
