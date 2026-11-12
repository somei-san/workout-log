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
        // 起動直後のシミュレーターは、キーボードが出るまでに時間がかかる
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        field.typeText(name)
        tap(button(part), part)
        shot("02-種目の追加-\(name)")
        tap(button("追加"), "追加")
    }

    func testWalkthrough() {
        app.launchEmpty()
        shot("01-ホーム-空")

        addExercise("ベンチプレス", part: "胸")
        addExercise("スクワット", part: "足")
        shot("03-ホーム-2種目")

        tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'ベンチプレス'")).firstMatch, "ベンチプレスのカード")
        shot("04-履歴-空")

        tap(button("新しい記録"), "新しい記録")
        shot("05-記録-新規")

        tap(button("＋ セットを追加"), "セットを追加")
        let fields = app.textFields.matching(identifier: "重さと回数")
        if fields.count >= 2 {
            // 数字以外の文字も打つ。「1a00」を 1 回の typeText で打つと欄に「1」だけが残ったので、分けて打つ
            for text in ["1", "a", "00"] {
                fields.element(boundBy: 0).typeText(text)
            }
            shot("06-記録-重さ入力中")
            XCTAssertEqual(fields.element(boundBy: 0).value as? String, "100", "重さの欄に数字以外の文字が残っている")
            // 「次へ」で重さから回数の欄へ移る
            tap(button("次へ"), "次へ 重さから回数")
            fields.element(boundBy: 1).typeText("5x")
            shot("07-記録-1セット目")
            XCTAssertEqual(fields.element(boundBy: 1).value as? String, "5", "回数の欄に数字以外の文字が残っている")
        } else {
            XCTFail("重さと回数の欄が無い")
        }
        // 回数の欄では、重さのボタンを出さない
        XCTAssertFalse(button("＋2.5").exists, "回数の欄で重さのボタンが出ている")
        fields.element(boundBy: 0).tap()
        tap(button("＋2.5"), "＋2.5")
        shot("08-記録-＋2.5")
        tap(button("＋ セットを追加"), "セットを追加 2 回目")
        if fields.count >= 4 {
            // 2 行目の重さは「前回と同じ」で 1 行目から写し、そのまま回数の欄へ移る
            tap(button("前回と同じ"), "前回と同じ")
            XCTAssertEqual(fields.element(boundBy: 2).value as? String, "102.5", "上の行の重さが写らない")
            fields.element(boundBy: 3).typeText("5")
            XCTAssertEqual(fields.element(boundBy: 3).value as? String, "5", "「前回と同じ」で回数の欄へ移らない")
            // 回数の次は RPE の欄
            tap(button("次へ"), "次へ 回数から RPE")
            let intensityFields = app.textFields.matching(identifier: "強度")
            intensityFields.element(boundBy: 1).typeText("8")
            XCTAssertEqual(intensityFields.element(boundBy: 1).value as? String, "8", "「次へ」で RPE の欄へ移らない")
            XCTAssertFalse(button("前回と同じ").exists, "RPE の欄で「前回と同じ」が出ている")
            // 打っている欄の上の余白を押しても、キーボードは閉じない
            intensityFields.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: -6)).tap()
            sleep(1)
            XCTAssertTrue(app.keyboards.firstMatch.exists, "打っている欄の余白を押すと、キーボードが閉じる")
            shot("09-記録-2セット目")
            // 最後の行の最後の欄では、空の行を足して、その行の重さへ移る
            tap(button("次へ"), "次へ 最後の欄")
            XCTAssertTrue(fields.element(boundBy: 4).waitForExistence(timeout: 3), "最後の欄の「次へ」で行が増えない")
            fields.element(boundBy: 4).typeText("60")
            XCTAssertEqual(fields.element(boundBy: 4).value as? String, "60", "足した行の重さの欄へ移らない")
            // 打っている欄は、キーボードの上のボタンの並びより上に出る
            XCTAssertLessThan(fields.element(boundBy: 4).frame.maxY, button("次へ").frame.minY, "打っている欄がボタンに隠れる")
            shot("09b-記録-足した行")
            // メモを打つときも、欄がキーボードに隠れない
            let memo = app.textFields["メモ"]
            tap(memo, "メモ")
            memo.typeText("メモ")
            // 数字のキーパッドから文字のキーボードに替わり、大きさが変わり終えてから送るので、送り終えるまで待つ。
            // CI では 1 回確かめるのに数秒かかることがあるので、何回か確かめ直せる上限にする
            let keyboard = app.keyboards.firstMatch
            let memoAboveKeyboard = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in memo.frame.maxY < keyboard.frame.minY }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [memoAboveKeyboard], timeout: 10), .completed, "メモの欄がキーボードに隠れる")
            shot("09c-記録-メモ")
        } else {
            XCTFail("2 行目の重さと回数の欄が無い")
        }
        app.closeKeyboard()

        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS '▾'")).firstMatch, "日付")
        let datePicker = app.datePickers.firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "日付のシートが出ない")
        shot("10-日付と時刻")
        tap(button("キャンセル"), "キャンセル")
        if !datePicker.waitForNonExistence(timeout: 5) {
            shot("10b-キャンセルで閉じない")
            XCTFail("キャンセルで日付のシートが閉じない")
            tap(button("完了"), "完了")
            if !datePicker.waitForNonExistence(timeout: 5) {
                XCTFail("完了でも日付のシートが閉じない")
                app.swipeDown()
                _ = datePicker.waitForNonExistence(timeout: 5)
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

        tap(button("データを読み込む"), "データを読み込む")
        shot("18-CSVの読み込み")
        app.swipeUp()
        shot("19-CSVの読み込み-下")
    }
}
