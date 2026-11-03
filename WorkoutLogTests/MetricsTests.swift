import Foundation
import Testing
@testable import WorkoutLog

struct MetricsTests {
    private func sets(_ values: [(Double, Int)]) -> [WorkoutSet] {
        values.enumerated().map { WorkoutSet(recordId: 0, position: $0.offset, weight: $0.element.0, reps: $0.element.1) }
    }

    private func summary(_ values: [(Double, Int)]) -> RecordSummary {
        RecordSummary(record: WorkoutRecord(exerciseId: 0, performedAt: Date()), sets: sets(values))
    }

    @Test(arguments: [(100.0, 1, 100.0), (100.0, 10, 3600.0 / 27), (60.0, 36, 2160.0)])
    func 推定1RMはBrzycki式で求める(weight: Double, reps: Int, expected: Double) {
        #expect(abs(WorkoutSet(recordId: 0, position: 0, weight: weight, reps: reps).estimated1RM - expected) < 1e-9)
    }

    @Test(arguments: [37, 50])
    func 推定1RMは式の割る数が0以下になる回数では重さをそのまま使う(reps: Int) {
        #expect(WorkoutSet(recordId: 0, position: 0, weight: 60, reps: reps).estimated1RM == 60)
    }

    @Test func ボリュームは全セットの重さ掛ける回数の合計() {
        #expect(summary([(100, 5), (97.5, 6), (0, 10)]).volume == 1085)
    }

    @Test func 推定1RMと最大重量はセットのうち最も高い値() {
        let s = summary([(100, 1), (90, 10), (95, 3)])
        // 90kg × 10 回: 90 × 36 ÷ 27
        #expect(s.estimated1RM == 120.0)
        #expect(s.maxWeight == 100)
    }

    @Test func トップセットは最も重いセットで_同じ重さなら回数の多いほう() {
        let top = summary([(100, 5), (100, 8), (90, 10)]).topSet
        #expect(top?.weight == 100)
        #expect(top?.reps == 8)
    }

    @Test func セットが無ければ推定1RMと最大重量とトップセットは無い() {
        let s = summary([])
        #expect(s.volume == 0)
        #expect(s.estimated1RM == nil)
        #expect(s.maxWeight == nil)
        #expect(s.topSet == nil)
    }

    @Test(arguments: [(135.0, "135"), (132.5, "132.5"), (0.0, "0"), (102.25, "102.25")])
    func 重さは整数なら小数点を付けない(value: Double, text: String) {
        #expect(Format.weight(value) == text)
    }

    @Test func 種目の履歴の推定1RMと最大重量は小数1桁で_値が無ければダッシュ() {
        #expect(Format.decimal(1300) == "1300.0")
        #expect(Format.decimal(133.333) == "133.3")
        #expect(Format.decimal(nil) == "–")
    }

    @Test func 日付は記録した場所のタイムゾーンで曜日と時刻を付けて出せる() throws {
        let date = try Date("2026-10-17T09:30:00Z", strategy: .iso8601)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(Format.date(date, timeZone: tokyo) == "2026/10/17")
        #expect(Format.date(date, timeZone: tokyo, weekday: true) == "2026/10/17(土)")
        #expect(Format.date(date, timeZone: tokyo, time: true) == "2026/10/17 18:30")
        #expect(Format.date(date, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2026/10/17")
        #expect(Format.date(try Date("2026-10-17T06:00:00Z", strategy: .iso8601), timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2026/10/16")
    }

    @Test func 種目の履歴の表示項目の初期値はボリュームと推定1RMと最大重量() {
        #expect(HistoryColumn.decode(HistoryColumn.initialRaw) == [.volume, .estimated1RM, .maxWeight])
    }

    @Test func 表示項目は項目の並び順で保存し_知らない項目は読み飛ばす() {
        #expect(HistoryColumn.encode([.setCount, .volume, .topSet]) == "volume,topSet,setCount")
        #expect(HistoryColumn.decode("setCount,unknown") == [.setCount])
    }

    @Test func 表示項目が1つも読めなければ初期値に戻す() {
        #expect(HistoryColumn.decode("") == HistoryColumn.defaults)
        #expect(HistoryColumn.decode("unknown") == HistoryColumn.defaults)
    }

    @Test func 表示項目は最後の1つを非表示にできない() {
        #expect(HistoryColumn.toggled([.volume, .topSet], .topSet, isOn: false) == [.volume])
        #expect(HistoryColumn.toggled([.volume], .setCount, isOn: true) == [.volume, .setCount])
        #expect(HistoryColumn.toggled([.volume], .volume, isOn: false) == nil)
    }

    @Test func 種目の履歴の各項目の値() {
        let s = summary([(100, 5), (100, 8), (90, 10)])
        #expect(HistoryColumn.volume.value(s) == "2200")
        #expect(HistoryColumn.estimated1RM.value(s) == "124.1")
        #expect(HistoryColumn.maxWeight.value(s) == "100.0")
        #expect(HistoryColumn.topSet.value(s) == "100×8")
        #expect(HistoryColumn.setCount.value(s) == "3")
        #expect(HistoryColumn.topSet.value(summary([])) == "–")
    }

    @Test func 強度の初期値はRPE() {
        #expect(IntensityKind.initial == .rpe)
    }
}
