import GRDB
import SwiftUI

/// 種目の履歴
struct HistoryView: View {
    let exerciseId: Int64
    @Binding var path: [Route]

    @Environment(\.appDatabase) private var database
    @State private var exercise: Exercise?
    @State private var summaries: [RecordSummary] = []

    var body: some View {
        List {
            Section {
                ForEach(summaries) { summary in
                    NavigationLink(value: Route.record(recordId: summary.record.id!)) {
                        HistoryRow(summary: summary, showsTime: summary.record.sharesDay(with: summaries.map(\.record)))
                    }
                }
            } header: {
                Text("ボリューム / 推定 1RM / 最大重量(kg)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView("記録がありません", systemImage: "list.bullet", description: Text("右上の「＋」で記録を始めます"))
            }
        }
        .navigationTitle(exercise?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新しい記録", systemImage: "plus") {
                    path.append(.newRecord(exerciseId: exerciseId, token: UUID()))
                }
            }
        }
        .task {
            let exerciseId = exerciseId
            let observation = ValueObservation.tracking { db in
                (try Exercise.fetchOne(db, id: exerciseId), try RecordSummary.fetchAll(db, exerciseId: exerciseId))
            }
            do {
                for try await (exercise, summaries) in observation.values(in: database.reader) {
                    self.exercise = exercise
                    self.summaries = summaries
                }
            } catch {
                print("種目の履歴を読めない: \(error)")
            }
        }
    }
}

private struct HistoryRow: View {
    let summary: RecordSummary
    let showsTime: Bool

    var body: some View {
        HStack {
            Text("\(Format.decimal(summary.volume)) / \(Format.decimal(summary.estimated1RM)) / \(Format.decimal(summary.maxWeight))")
                .monospacedDigit()
            Spacer()
            if !summary.record.memo.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("メモあり")
            }
            Text(Format.date(summary.record.performedAt, timeZone: summary.record.timeZone, time: showsTime))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
    }
}
