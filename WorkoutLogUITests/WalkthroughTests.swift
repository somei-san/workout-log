import XCTest

/// 画面を順にたどり、各画面のスクリーンショットを残す
@MainActor
final class WalkthroughTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    /// 見つからなくてもテストを止めずに先へ進む
    private func tap(_ element: XCUIElement, _ note: String) {
        if element.waitForExistence(timeout: 3) {
            element.tap()
        } else {
            XCTFail("見つからない: \(note)")
        }
    }

    private func back() {
        tap(app.buttons["BackButton"].firstMatch, "戻る")
        sleep(1)
    }

    private func addExercise(_ name: String, part: String) {
        tap(button("種目を追加"), "種目を追加")
        let field = app.textFields["例: ベンチプレス"]
        tap(field, "名前")
        field.typeText(name)
        tap(button(part), part)
        shot("02-種目の追加-\(name)")
        tap(button("追加"), "追加")
    }

    func testWalkthrough() {
        app.launch()
        shot("01-ホーム-空")

        addExercise("ベンチプレス", part: "胸")
        addExercise("スクワット", part: "足")
        shot("03-ホーム-2種目")

        tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'ベンチプレス'")).firstMatch, "ベンチプレスのカード")
        shot("04-履歴-空")

        tap(button("新しい記録"), "新しい記録")
        shot("05-記録-新規")

        tap(button("行を足す"), "行を足す")
        let fields = app.textFields.matching(identifier: "–")
        if fields.count >= 2 {
            fields.element(boundBy: 0).typeText("100")
            shot("06-記録-重さ入力中")
            fields.element(boundBy: 1).tap()
            fields.element(boundBy: 1).typeText("5")
            shot("07-記録-1セット目")
        } else {
            XCTFail("重さと回数の欄が無い")
        }
        tap(button("＋2.5"), "＋2.5")
        shot("08-記録-＋2.5")
        tap(button("閉じる"), "閉じる")
        tap(button("行を足す"), "行を足す 2 回目")
        shot("09-記録-2セット目")
        if button("閉じる").exists { button("閉じる").tap() }

        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS '▾'")).firstMatch, "日付")
        sleep(2)
        shot("10-日付と時刻")
        tap(button("キャンセル"), "キャンセル")
        sleep(2)
        if app.datePickers.firstMatch.exists {
            shot("10b-キャンセルで閉じない")
            XCTFail("キャンセルで日付のシートが閉じない")
            tap(button("完了"), "完了")
            sleep(2)
            if app.datePickers.firstMatch.exists {
                XCTFail("完了でも日付のシートが閉じない")
                app.swipeDown()
                sleep(2)
            }
        }

        back()
        shot("11-履歴-1件")
        XCTAssertTrue(app.staticTexts["1025 / 115.3 / 102.5"].exists, "履歴のボリュームが整数で出ていない")

        tap(button("この種目の分析"), "分析")
        shot("12-分析")
        back()
        back()
        shot("13-ホーム-記録後")

        tap(button("部位"), "部位")
        shot("14-ホーム-部位")

        tap(button("並べ替え"), "並べ替え")
        shot("15-並べ替え")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.9)).tap()

        let squat = app.buttons.containing(NSPredicate(format: "label CONTAINS 'スクワット'")).firstMatch
        if squat.waitForExistence(timeout: 3) {
            squat.press(forDuration: 1.2)
            shot("16-長押しメニュー")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.9)).tap()
        }

        tap(button("設定"), "設定")
        shot("17-設定")
    }
}
