import XCTest

/// 種目の記録でのセットの入力と削除
@MainActor
final class RecordTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// 種目を入れて起動し、新しい記録を開いて、重さと回数を入れた 1 セットを作る
    private func recordOneSet(languageIsEnglish: Bool = false) throws {
        app.launchEmpty(languageIsEnglish: languageIsEnglish, exercises: [("懸垂", "back")])
        app.card("懸垂").tap()
        app.buttons["新しい記録"].tap()
        XCTAssertTrue(app.buttons["＋ セットを追加"].waitToAppear(timeout: 5))
        try app.addSet(weight: "20", reps: "8")
    }

    func test最後のセットを消すときは確認を出し_記録ごと消して履歴に戻る() throws {
        try recordOneSet()
        app.swipeToDelete(app.textFields.matching(identifier: "重さと回数").element(boundBy: 0))
        let confirm = app.buttons["記録を削除"]
        XCTAssertTrue(confirm.waitToAppear(timeout: 5), "最後のセットで確認が出ない")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["記録がありません"].waitToAppear(timeout: 5))
    }

    func test前日以前の記録は閲覧モードで開き_編集と完了で切り替わる() throws {
        try recordOneSet(languageIsEnglish: true)
        let dateButton = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch
        dateButton.tap()
        // 前の月の 15 日は、テストをいつ実行しても前日以前になる
        let picker = app.datePickers["日付"]
        XCTAssertTrue(picker.waitToAppear(timeout: 5))
        picker.buttons["DatePicker.PreviousMonth"].tap()
        picker.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " 15")).firstMatch.tap()
        app.buttons["完了"].tap()

        app.buttons["BackButton"].firstMatch.tap()
        let summary = app.staticTexts["160 / 24.8 / 20.0"]
        XCTAssertTrue(summary.waitToAppear(timeout: 5))
        summary.tap()

        let edit = app.buttons["編集"]
        XCTAssertTrue(edit.waitToAppear(timeout: 5), "前日以前の記録が閲覧モードで開かない")
        XCTAssertEqual(app.textFields.matching(identifier: "重さと回数").count, 0)
        XCTAssertTrue(app.staticTexts["20"].exists)
        XCTAssertFalse(app.buttons["＋ セットを追加"].exists)
        XCTAssertFalse(dateButton.exists)
        app.staticTexts["20"].swipeLeft()
        XCTAssertFalse(app.buttons["削除"].waitForExistence(timeout: 2), "閲覧モードで行を消せる")

        edit.tap()
        XCTAssertTrue(app.buttons["＋ セットを追加"].waitToAppear(timeout: 5))
        XCTAssertEqual(app.textFields.matching(identifier: "重さと回数").count, 2)
        XCTAssertTrue(dateButton.exists)

        app.buttons["完了"].tap()
        XCTAssertTrue(edit.waitToAppear(timeout: 5))
        // 「編集」が出るのと、「＋ セットを追加」が消えるのが同時とは限らないので、消えるまで待つ
        XCTAssertTrue(app.buttons["＋ セットを追加"].waitToDisappear(timeout: 5))

        // 2 回目に開いた「新しい記録」は、1 回目の記録を「前回」として出す
        app.buttons["BackButton"].firstMatch.tap()
        app.buttons["新しい記録"].tap()
        XCTAssertTrue(app.staticTexts["前回  20kg×8"].waitToAppear(timeout: 5), "2 回目の「新しい記録」に「前回」が出ない")
    }

    func test数字の欄は左の端を押しても_カーソルが数字の一番右に来る() throws {
        try recordOneSet()
        app.type("8", into: app.textFields["強度"])
        try app.closeKeyboard()
        let fields = app.textFields.matching(identifier: "重さと回数")
        // 右寄せの欄の、数字より左の空いたところを押す。カーソルが一番左に来ると、⌫ を押しても消えない
        let cases = [(fields.element(boundBy: 0), "2"), (fields.element(boundBy: 1), ""), (app.textFields["強度"], "")]
        for (field, expected) in cases {
            for _ in 0..<3 {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
                if app.keyboards.firstMatch.waitToAppear(timeout: 5) { break }
            }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            // 入力中の欄は「–」を出さないので、空になると値は空文字になる
            XCTAssertEqual(field.value as? String, expected, "⌫ で右から 1 文字消えない")
            try app.closeKeyboard()
        }
    }
}
