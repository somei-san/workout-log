import XCTest

@MainActor
extension XCUIApplication {
    /// 空のデータベースと空の設定で起動する。languageIsEnglish なら端末の言語を英語にする。
    /// 日付のシートのカレンダーの日のラベルは、アプリが日本語のロケールを指定していても英語で出たため
    func launchEmpty(languageIsEnglish: Bool = false) {
        launchArguments = ["-uiTesting"] + (languageIsEnglish ? ["-AppleLanguages", "(en)"] : [])
        launch()
    }

    /// ホームの「＋」から、最初に並べるセット数を initialRowCount にした種目を足す。
    /// 名前が空の間は「追加」を押せないことと、セット数が表示に出ることも確かめる
    func addExercise(_ name: String, part: String, initialRowCount: Int = 0) {
        buttons["種目を追加"].tap()
        let add = buttons["追加"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled, "名前が空なのに「追加」を押せる")
        type(name, into: textFields["例: ベンチプレス"])
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch.tap()
        // Stepper の 2 つ目のボタンが「＋」。ボタンの名前は端末の言語で変わるので、順番で選ぶ
        for _ in 0..<initialRowCount {
            steppers.firstMatch.buttons.element(boundBy: 1).tap()
        }
        XCTAssertTrue(steppers["空の行の数  \(initialRowCount)"].exists)
        // 入力の直後は、まだ押せる状態になっていないことがある
        XCTAssertTrue(add.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        add.tap()
    }

    /// 欄をタップして文字を打つ。
    /// タップしても欄にフォーカスが移らないことがあるので、キーボードが出るまでタップし直す
    func type(_ text: String, into field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if keyboards.firstMatch.waitForExistence(timeout: 5) { break }
        }
        field.typeText(text)
    }

    /// 行を左にスワイプして「削除」を押す。スワイプしても「削除」が出ないことがあるので、出なければスワイプし直す
    func swipeToDelete(_ row: XCUIElement) {
        let delete = buttons["削除"]
        for _ in 0..<3 {
            row.swipeLeft()
            if delete.waitForExistence(timeout: 3) { break }
        }
        delete.tap()
    }

    /// キーボードの上の「閉じる」で、キーボードを閉じる。キーボードが出ていなければ何もしない
    func closeKeyboard() {
        let close = buttons["閉じる"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        }
    }

    /// ホームの種目のカード
    func card(_ name: String) -> XCUIElement {
        buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
