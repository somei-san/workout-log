import XCTest

/// ホームでの種目の非表示と削除
@MainActor
final class ExerciseTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    private func menu(_ name: String, _ item: String) {
        let card = app.card(name)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "長押しのメニューに「\(item)」が無い")
        button.tap()
    }

    func test種目の削除は削除と入力するまで押せない() {
        app.launchEmpty()
        app.addExercise("懸垂", part: "背中")
        menu("懸垂", "削除")

        let delete = app.buttons["この種目を削除する"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled)
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("さくじょ")
        XCTAssertFalse(delete.isEnabled, "「削除」以外の文字で押せる")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "削除")
        XCTAssertTrue(delete.isEnabled)
        delete.tap()

        XCTAssertTrue(app.staticTexts["種目がありません"].waitForExistence(timeout: 5))
    }

    func test非表示にした種目は非表示の種目にまとまり_再表示で戻る() {
        app.launchEmpty()
        app.addExercise("懸垂", part: "背中")
        app.addExercise("ディップス", part: "胸")
        menu("懸垂", "非表示")

        let hidden = app.buttons["非表示の種目(1)"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        // 普段は閉じている
        XCTAssertFalse(app.card("懸垂").exists)
        hidden.tap()
        menu("懸垂", "再表示")

        XCTAssertTrue(app.card("懸垂").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["非表示の種目(1)"].exists)
    }
}
