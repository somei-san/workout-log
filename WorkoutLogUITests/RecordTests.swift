import XCTest

/// 種目の記録でのセットの入力と削除
@MainActor
final class RecordTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// 種目を足し、新しい記録を開いて、重さと回数を入れた 1 セットを作る
    private func recordOneSet(languageIsEnglish: Bool = false) {
        app.launchEmpty(languageIsEnglish: languageIsEnglish)
        app.addExercise("懸垂", part: "背中")
        app.card("懸垂").tap()
        app.buttons["新しい記録"].tap()
        let add = app.buttons["行を足す"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let fields = app.textFields.matching(identifier: "–")
        XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5))
        app.type("20", into: fields.element(boundBy: 0))
        app.type("8", into: fields.element(boundBy: 1))
        app.closeKeyboard()
    }

    func test最後のセットを消すときは確認を出し_記録ごと消して履歴に戻る() {
        recordOneSet()
        // 足した行は、直前のセットの値が入ってセットになる
        app.buttons["行を足す"].tap()
        let fields = app.textFields.matching(identifier: "–")
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields.element(boundBy: 2).value as? String, "20")
        XCTAssertEqual(fields.element(boundBy: 3).value as? String, "8")

        // 2 つのうち 1 つを消すときは確認を出さない
        app.swipeToDelete(app.textFields.matching(identifier: "–").element(boundBy: 2))
        XCTAssertFalse(app.buttons["記録を削除"].waitForExistence(timeout: 2), "最後ではないセットで確認が出た")
        XCTAssertEqual(app.textFields.matching(identifier: "–").count, 2)

        app.swipeToDelete(app.textFields.matching(identifier: "–").element(boundBy: 0))
        let confirm = app.buttons["記録を削除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "最後のセットで確認が出ない")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["記録がありません"].waitForExistence(timeout: 5))
    }

    func test前日以前の記録は閲覧モードで開き_編集と完了で切り替わる() {
        recordOneSet(languageIsEnglish: true)
        let dateButton = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch
        dateButton.tap()
        // 前の月の 15 日は、テストをいつ実行しても前日以前になる
        let picker = app.datePickers["日付"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["DatePicker.PreviousMonth"].tap()
        picker.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " 15")).firstMatch.tap()
        app.buttons["完了"].tap()

        app.buttons["BackButton"].firstMatch.tap()
        let summary = app.staticTexts["160 / 24.8 / 20.0"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()

        let edit = app.buttons["編集"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "前日以前の記録が閲覧モードで開かない")
        XCTAssertEqual(app.textFields.matching(identifier: "–").count, 0)
        XCTAssertTrue(app.staticTexts["20"].exists)
        XCTAssertFalse(app.buttons["行を足す"].exists)
        XCTAssertFalse(dateButton.exists)
        app.staticTexts["20"].swipeLeft()
        XCTAssertFalse(app.buttons["削除"].waitForExistence(timeout: 2), "閲覧モードで行を消せる")

        edit.tap()
        XCTAssertTrue(app.buttons["行を足す"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.matching(identifier: "–").count, 2)
        XCTAssertTrue(dateButton.exists)

        app.buttons["完了"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["行を足す"].exists)
    }

    func test履歴に戻ると記録の値が出て_次の記録では前回として出る() {
        recordOneSet()
        app.buttons["BackButton"].firstMatch.tap()
        // ボリューム / 推定 1RM / 最大重量
        XCTAssertTrue(app.staticTexts["160 / 24.8 / 20.0"].waitForExistence(timeout: 5))

        app.buttons["新しい記録"].tap()
        XCTAssertTrue(app.staticTexts["前回  20kg×8"].waitForExistence(timeout: 5))
    }
}
