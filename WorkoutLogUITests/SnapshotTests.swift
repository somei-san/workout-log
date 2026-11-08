import SnapshotTesting
import XCTest

/// 各画面の見た目を、基準の画像（WorkoutLogUITests/__Snapshots__）と比べる。このクラスはライト・標準の文字サイズで撮り、
/// ダークと大きい文字サイズは、このクラスを継承したクラスで撮る。撮るシミュレーターは scripts/vrt-simulator.sh で用意する
@MainActor
class SnapshotTests: XCTestCase {
    class var isDark: Bool { false }
    class var isLargeText: Bool { false }

    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
    }

    /// 空のデータベースと空の設定で、撮る条件をそろえて起動する
    private func launch() {
        app.launchArguments = [
            "-uiTesting",
            // 日付のシートのカレンダーは本当の今日に印を付けるので、テストを回す月と重ならない月の日にする
            "-uiTestingNow", "2026-01-15T01:00:00Z",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
            "-uiTestingDark", Self.isDark ? "YES" : "NO",
        ] + (Self.isLargeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] : [])
        // 手元と CI でタイムゾーンが違っても、同じ日付と時刻を出す
        app.launchEnvironment["TZ"] = "Asia/Tokyo"
        app.launch()
    }

    /// 今の画面を撮って、基準の画像と比べる。画像の名前の先頭に、撮った条件を付ける
    private func snapshot(_ name: String, file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        // 画面の切り替えやキーパッドが出るアニメーションの途中で撮らないよう、画面が変わらなくなるまで待つ。
        // カーソルが点滅している画面は変わり続けるので、待つ回数に上限を置く
        var screen = XCUIScreen.main.screenshot().pngRepresentation
        for _ in 0..<10 {
            usleep(500_000)
            let next = XCUIScreen.main.screenshot().pngRepresentation
            if next == screen { break }
            screen = next
        }
        let condition = "\(Self.isDark ? "dark" : "light")-\(Self.isLargeText ? "large" : "standard")"
        assertSnapshot(
            of: UIImage(data: screen)!,
            as: .image(precision: 0.999, perceptualPrecision: 0.98),
            named: "\(condition)-\(name)",
            file: file, testName: testName, line: line
        )
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func back() {
        app.buttons["BackButton"].firstMatch.tap()
    }

    /// 1 つずつ打ち、キーパッドが出た状態で終える。キーパッドが出なければ false を返す。
    /// 数字以外の文字を打つと、欄からフォーカスが外れてキーパッドが閉じることがあるため、閉じていれば欄を押し直す
    private func typeEach(_ texts: [String], into field: XCUIElement) -> Bool {
        for (i, text) in texts.enumerated() {
            // 2 つ目からは、キーパッドが出ていれば押し直さずに打つ
            if i > 0, app.keyboards.firstMatch.exists {
                field.typeText(text)
                continue
            }
            tapEnd(of: field)
            guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else { return false }
            field.typeText(text)
        }
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) { return true }
        tapEnd(of: field)
        return app.keyboards.firstMatch.waitForExistence(timeout: 5)
    }

    /// 欄の右端を押す。数字の欄は右に寄せて出すので、真ん中を押すと、打った数字の前にカーソルが置かれる
    private func tapEnd(of field: XCUIElement) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    func testHome() {
        launch()
        snapshot("1-empty")

        app.addExercise("ベンチプレス", part: "胸")
        app.addExercise("スクワット", part: "足")
        snapshot("2-exercises")

        // 別の画面から戻ったあとは、「部位」を押しても見方が切り替わらないことがある。
        // 見方を切り替えて撮る画面は、種目の履歴に移る前に撮る
        // 押しても切り替わらないことがあるので、切り替わるまで押し直す
        for _ in 0..<3 {
            app.buttons["部位"].tap()
            if app.staticTexts["胸"].waitForExistence(timeout: 5) { break }
        }
        guard app.staticTexts["胸"].exists else { return XCTFail("部位ごとの見方に切り替わらない") }
        snapshot("3-by-part")

        app.card("ベンチプレス").tap()
        app.buttons["新しい記録"].tap()
        app.addSet(weight: "100", reps: "5")
        // 戻る途中でもう一度戻ると、ホームの上のボタンがぼやけたままになることがある。種目の履歴が出てから戻る
        back()
        guard app.buttons["新しい記録"].waitForExistence(timeout: 5) else { return XCTFail("種目の履歴に戻らない") }
        back()
        guard app.buttons["部位"].waitForExistence(timeout: 5) else { return XCTFail("ホームに戻らない") }
        snapshot("4-recorded")
    }

    func testExerciseForm() {
        launch()
        app.buttons["種目を追加"].tap()
        XCTAssertTrue(app.buttons["追加"].waitForExistence(timeout: 5))
        snapshot("1-empty")

        let name = app.textFields["例: ベンチプレス"]
        app.type("ベンチプレス", into: name)
        // 打った直後は、欄の値に一部の文字しか入っていないことがある
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "ベンチプレス"), object: name)
        guard XCTWaiter.wait(for: [filled], timeout: 5) == .completed else { return XCTFail("名前の欄に入力できない: \(String(describing: name.value))") }
        button("胸").tap()
        snapshot("2-filled")
    }

    func testRecord() {
        launch()
        app.addExercise("ベンチプレス", part: "胸")
        app.card("ベンチプレス").tap()
        app.buttons["新しい記録"].tap()
        XCTAssertTrue(app.buttons["＋ セットを追加"].waitForExistence(timeout: 5))
        snapshot("1-new")

        app.buttons["＋ セットを追加"].tap()
        let fields = app.textFields.matching(identifier: "重さと回数")
        XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5))
        let weight = fields.element(boundBy: 0), reps = fields.element(boundBy: 1)
        // 足した行の重さの欄に、カーソルが移ってキーパッドが出る
        guard app.keyboards.firstMatch.waitForExistence(timeout: 10) else { return XCTFail("キーパッドが出ない") }
        snapshot("2-keypad")

        // 数字以外の文字も打つ
        guard typeEach(["1", "a", "00"], into: weight) else { return XCTFail("キーパッドが出ない") }
        guard weight.value as? String == "100" else { return XCTFail("重さの欄が 100 にならない: \(String(describing: weight.value))") }
        snapshot("3-typing-weight")

        guard typeEach(["5", "x"], into: reps) else { return XCTFail("キーパッドが出ない") }
        guard reps.value as? String == "5" else { return XCTFail("回数の欄が 5 にならない: \(String(describing: reps.value))") }
        snapshot("4-typing-reps")

        button("＋2.5").tap()
        guard weight.value as? String == "102.5" else { return XCTFail("＋2.5 で重さが 102.5 にならない") }
        snapshot("5-plus-2.5")

        app.closeKeyboard()
        snapshot("6-one-set")

        app.addSet(weight: "102.5", reps: "5")
        snapshot("7-two-sets")
    }

    func testDateSheet() {
        launch()
        app.addExercise("ベンチプレス", part: "胸")
        app.card("ベンチプレス").tap()
        app.buttons["新しい記録"].tap()
        // 日付を押しても日付のシートが出ないことがあるので、出るまで押し直す
        let datePicker = app.datePickers.firstMatch
        for _ in 0..<3 {
            app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch.tap()
            if datePicker.waitForExistence(timeout: 5) { break }
        }
        guard datePicker.exists else { return XCTFail("日付のシートが出ない") }
        snapshot("1-sheet")

        button("キャンセル").tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForNonExistence(timeout: 5), "キャンセルで日付のシートが閉じない")
    }

    func testHistoryAndAnalysis() {
        launch()
        app.addExercise("ベンチプレス", part: "胸")
        app.card("ベンチプレス").tap()
        XCTAssertTrue(app.buttons["新しい記録"].waitForExistence(timeout: 5))
        snapshot("1-history-empty")

        app.buttons["新しい記録"].tap()
        app.addSet(weight: "102.5", reps: "5")
        app.addSet(weight: "102.5", reps: "5")
        back()
        // ボリューム / 推定 1RM / 最大重量。ボリュームは整数で出す
        XCTAssertTrue(app.staticTexts["1025 / 115.3 / 102.5"].waitForExistence(timeout: 5), "履歴のボリュームが整数で出ていない")
        snapshot("2-history")

        button("この種目の分析").tap()
        snapshot("3-analysis")
    }

    func testSettings() {
        launch()
        button("設定").tap()
        XCTAssertTrue(app.buttons["BackButton"].firstMatch.waitForExistence(timeout: 5), "設定の画面に移らない")
        snapshot("1-settings")
    }
}

final class DarkSnapshotTests: SnapshotTests {
    override class var isDark: Bool { true }
}

/// 大きい文字サイズは、アクセシビリティの設定を使わずに選べる中で一番大きいもの（XXXL）にする
final class LargeTextSnapshotTests: SnapshotTests {
    override class var isLargeText: Bool { true }
}

final class DarkLargeTextSnapshotTests: SnapshotTests {
    override class var isDark: Bool { true }
    override class var isLargeText: Bool { true }
}
