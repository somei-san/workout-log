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
        let button = app.buttons[item]
        // 長押ししてもメニューが出ないことがある。種目の履歴に移っていればホームに戻り、長押しし直す
        for _ in 0..<3 {
            XCTAssertTrue(card.waitToAppear(timeout: 5))
            card.press(forDuration: 1.5)
            if button.waitToAppear(timeout: 5) { break }
            let back = app.buttons["BackButton"].firstMatch
            if back.exists { back.tap() }
        }
        XCTAssertTrue(button.exists, "長押しのメニューに「\(item)」が無い")
        button.tap()
    }

    func test種目の削除は削除と入力するまで押せない() {
        app.launchEmpty(exercises: [("懸垂", "back")])
        menu("懸垂", "削除")

        let delete = app.buttons["この種目を削除する"]
        XCTAssertTrue(delete.waitToAppear(timeout: 5))
        XCTAssertFalse(delete.isEnabled)
        let field = app.textFields.firstMatch
        app.type("削", into: field)
        XCTAssertFalse(delete.isEnabled, "「削除」と入力し終える前に押せる")
        field.typeText("除")
        // 入力の直後は、まだ押せる状態になっていないことがある
        XCTAssertTrue(delete.waitToBeEnabled(timeout: 5))
        delete.tap()

        XCTAssertTrue(app.staticTexts["種目がありません"].waitToAppear(timeout: 5))
    }

    func test非表示にした種目は非表示の種目にまとまり_再表示で戻る() {
        app.launchEmpty(exercises: [("懸垂", "back"), ("ディップス", "chest")])
        menu("懸垂", "非表示")

        let hidden = app.buttons["非表示の種目(1)"]
        XCTAssertTrue(hidden.waitToAppear(timeout: 5))
        // 普段は閉じている。「非表示の種目」が出るのと、カードが消えるのが同時とは限らないので、消えるまで待つ
        XCTAssertTrue(app.card("懸垂").waitToDisappear(timeout: 5))
        hidden.tap()
        menu("懸垂", "再表示")

        XCTAssertTrue(app.card("懸垂").waitToAppear(timeout: 5))
        XCTAssertTrue(app.buttons["非表示の種目(1)"].waitToDisappear(timeout: 5))
    }
}
