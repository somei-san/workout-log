import Foundation
import Testing
@testable import WorkoutLog

struct AnalysisTests {
    let today: LocalDay

    init() throws {
        today = LocalDay(try Date("2026-10-17T12:00:00Z", strategy: .iso8601), timeZone: .gmt)
    }

    /// 日付ごとに、重さ value kg × 1 回のセット 1 つの記録を、古い順に作る
    private func summaries(_ items: [(day: String, value: Double)]) throws -> [RecordSummary] {
        try items.map { item in
            RecordSummary(record: WorkoutRecord(exerciseId: 0, performedAt: try Date(item.day + "T12:00:00Z", strategy: .iso8601), timeZone: .gmt),
                          sets: [WorkoutSet(recordId: 0, position: 0, weight: item.value, reps: 1)])
        }
    }

    private func values(_ points: [AnalysisView.Point]) -> [Double] {
        points.map(\.value)
    }

    @Test func 指標は推定1RMと最大重量とボリュームから選ぶ() throws {
        let record = WorkoutRecord(exerciseId: 0, performedAt: try Date("2026-10-10T12:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let s = [RecordSummary(record: record, sets: [
            WorkoutSet(recordId: 0, position: 0, weight: 100, reps: 5),
            WorkoutSet(recordId: 0, position: 1, weight: 90, reps: 10),
        ])]
        func value(_ metric: AnalysisView.Metric) -> [Double] {
            values(AnalysisView.points(s, metric: metric, range: .all, display: .raw, today: today))
        }
        // 90kg × 10 回の推定 1RM 120 が、100kg × 5 回の 112.5 より高い
        #expect(value(.estimated1RM) == [120])
        #expect(value(.maxWeight) == [100])
        #expect(value(.volume) == [1400])
    }

    @Test func 記録ごとは各記録の値をそのまま出す() throws {
        let s = try summaries([("2026-10-01", 100), ("2026-10-08", 110)])
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .all, display: .raw, today: today)) == [100, 110])
        #expect(values(AnalysisView.points(s, metric: .volume, range: .all, display: .raw, today: today)) == [100, 110])
    }

    @Test func 移動平均はその記録を含む直近5回の平均で_5回に満たない間はそれまでの全記録の平均() throws {
        let s = try summaries((1...7).map { (String(format: "2026-10-%02d", $0), Double($0 * 10)) })
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .all, display: .movingAverage, today: today))
            == [10, 15, 20, 25, 30, 40, 50])
    }

    @Test func 期間はnか月前の翌日からの記録に絞る() throws {
        let s = try summaries([("2026-08-01", 1), ("2026-09-17", 2), ("2026-09-18", 3), ("2026-10-17", 4)])
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .month1, display: .raw, today: today)) == [3, 4])
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .month3, display: .raw, today: today)) == [1, 2, 3, 4])
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .all, display: .raw, today: today)) == [1, 2, 3, 4])
    }

    @Test func 期間で絞っても移動平均は期間より前の記録も含めて求める() throws {
        let s = try summaries([("2026-08-01", 10), ("2026-09-01", 20), ("2026-10-10", 30)])
        #expect(values(AnalysisView.points(s, metric: .maxWeight, range: .month1, display: .movingAverage, today: today)) == [20])
    }

    @Test func 期間に記録が無ければ点は無い() throws {
        let s = try summaries([("2025-01-01", 100)])
        #expect(AnalysisView.points(s, metric: .maxWeight, range: .year1, display: .raw, today: today).isEmpty)
    }
}
