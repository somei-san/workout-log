import XCTest

@MainActor
extension XCUIApplication {
    /// 空のデータベースと空の設定で起動する。exercises の種目は、起動したときから入れておく。
    /// languageIsEnglish なら端末の言語を英語にする。
    /// 日付のシートのカレンダーの日のラベルは、アプリが日本語のロケールを指定していても英語で出たため
    func launchEmpty(languageIsEnglish: Bool = false, exercises: [(name: String, part: String)] = []) {
        launchArguments = ["-uiTesting"] + (languageIsEnglish ? ["-AppleLanguages", "(en)"] : [])
            + Self.exerciseArguments(exercises)
        launch()
    }

    /// 種目を入れた状態で起動するための起動引数。part は部位の rawValue（chest、leg など）。
    /// 種目を足す画面を確かめるテストでなければ、画面の操作で足すより速い
    static func exerciseArguments(_ exercises: [(name: String, part: String)]) -> [String] {
        exercises.isEmpty ? [] : ["-uiTestingExercises", exercises.map { "\($0.name):\($0.part)" }.joined(separator: ",")]
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
        XCTAssertTrue(add.waitForNonExistence(timeout: 5), "「追加」で種目の追加のシートが閉じない")
    }

    /// 種目の記録で「＋ セットを追加」で行を足し、その行に重さと回数を入れる
    func addSet(weight: String, reps: String) {
        let fields = textFields.matching(identifier: "重さと回数")
        let count = fields.count
        buttons["＋ セットを追加"].tap()
        XCTAssertTrue(fields.element(boundBy: count + 1).waitForExistence(timeout: 5))
        type(weight, into: fields.element(boundBy: count))
        type(reps, into: fields.element(boundBy: count + 1))
        closeKeyboard()
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

    /// 記録の画面の上の「前回」の行を押して、キーボードを閉じる。入力欄の外を押すと閉じるため
    func closeKeyboard() {
        guard keyboards.firstMatch.waitForExistence(timeout: 2) else { return }
        staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "前回")).firstMatch.tap()
        XCTAssertTrue(keyboards.firstMatch.waitForNonExistence(timeout: 5), "入力欄の外を押してもキーボードが閉じない")
    }

    /// ホームの種目のカード
    func card(_ name: String) -> XCUIElement {
        buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
