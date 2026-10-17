import Charts
import GRDB
import SwiftUI

/// 分析。1 種目の推移を折れ線グラフで出す
struct AnalysisView: View {
    enum Metric: String, CaseIterable {
        case estimated1RM, maxWeight, volume

        var label: String {
            switch self {
            case .estimated1RM: HistoryColumn.estimated1RM.label
            case .maxWeight: HistoryColumn.maxWeight.label
            case .volume: HistoryColumn.volume.label
            }
        }

        func value(_ summary: RecordSummary) -> Double? {
            switch self {
            case .estimated1RM: summary.estimated1RM
            case .maxWeight: summary.maxWeight
            case .volume: summary.volume
            }
        }
    }

    enum Range: Int, CaseIterable {
        case month1 = 1, month3 = 3, month6 = 6, year1 = 12, all = 0

        var label: String {
            switch self {
            case .month1: "1 か月"
            case .month3: "3 か月"
            case .month6: "6 か月"
            case .year1: "1 年"
            case .all: "全期間"
            }
        }
    }

    enum Display: String, CaseIterable {
        case raw, movingAverage

        var label: String {
            switch self {
            case .raw: "記録ごと"
            case .movingAverage: "移動平均"
            }
        }
    }

    struct Point: Identifiable {
        var summary: RecordSummary
        var value: Double

        var id: Int64? { summary.id }
        var date: Date { summary.record.performedAt }
    }

    let exerciseId: Int64

    @Environment(\.appDatabase) private var database
    @State private var exercise: Exercise?
    /// 古い順
    @State private var summaries: [RecordSummary] = []
    @State private var metric = Metric.estimated1RM
    @State private var range = Range.month3
    @State private var display = Display.raw
    @State private var selectedDate: Date?

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Picker("指標", selection: $metric) {
                        ForEach(Metric.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("期間", selection: $range) {
                        ForEach(Range.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("表示", selection: $display) {
                        ForEach(Display.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                .pickerStyle(.segmented)
                chart
                    .frame(height: 220)
            }
            Section("直近の記録") {
                ForEach(summaries.suffix(5).reversed()) { summary in
                    HStack {
                        Text(Format.date(summary.record.performedAt, timeZone: summary.record.timeZone))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.sets(summary.sets))
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(exercise?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let exerciseId = exerciseId
            let observation = ValueObservation.tracking { db in
                (try Exercise.fetchOne(db, id: exerciseId), try RecordSummary.fetchAll(db, exerciseId: exerciseId))
            }
            do {
                for try await (exercise, summaries) in observation.values(in: database.reader) {
                    self.exercise = exercise
                    self.summaries = summaries.reversed()
                }
            } catch {
                print("分析の記録を読めない: \(error)")
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let points = self.points
        if points.isEmpty {
            ContentUnavailableView("この期間の記録はありません", systemImage: "chart.xyaxis.line")
        } else {
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("日付", point.date), y: .value(metric.label, point.value))
                    PointMark(x: .value("日付", point.date), y: .value(metric.label, point.value))
                }
                if let selected = nearest(points) {
                    RuleMark(x: .value("日付", selected.date))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(Format.date(selected.date, timeZone: selected.summary.record.timeZone))
                                Text(Format.decimal(selected.value)).bold()
                            }
                            .font(.caption)
                            .padding(6)
                            .background(.background, in: .rect(cornerRadius: 6))
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            // 指を離しても値を出したままにするため、chartXSelection ではなくタップで選ぶ
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { tap in
                    selectedDate = proxy.value(atX: tap.location.x, as: Date.self)
                }
            }
        }
    }

    /// 期間の中の点。移動平均は、期間より前の記録も含めた直近 5 回で求める
    private var points: [Point] {
        let values = summaries.map { metric.value($0) ?? 0 }
        let all = summaries.indices.map { i in
            let value = switch display {
            case .raw: values[i]
            case .movingAverage: values[max(0, i - 4)...i].reduce(0, +) / Double(min(i + 1, 5))
            }
            return Point(summary: summaries[i], value: value)
        }
        guard range != .all else { return all }
        let since = LocalDay.today().start(ofLastMonths: range.rawValue)
        return all.filter { $0.summary.record.day >= since }
    }

    private func nearest(_ points: [Point]) -> Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
}
