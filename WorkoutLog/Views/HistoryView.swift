import GRDB
import SwiftUI

/// 種目の履歴
struct HistoryView: View {
    let exerciseId: Int64
    @Binding var path: [Route]

    @Environment(\.appDatabase) private var database
    @State private var exercise: Exercise?
    @State private var summaries: [RecordSummary] = []
    @State private var isEditingExercise = false
    /// 削除の確認を出している 1 回の記録
    @State private var deleting: RecordSummary?

    private var isConfirmingDelete: Binding<Bool> {
        Binding { deleting != nil } set: { if !$0 { deleting = nil } }
    }

    private var deleteTitle: String {
        guard let record = deleting?.record else { return "" }
        return Format.date(record.performedAt, timeZone: record.timeZone, weekday: true) + " の記録を削除"
    }

    private func delete(_ record: WorkoutRecord) {
        do {
            _ = try database.writer.write { db in try record.delete(db) }
        } catch {
            print("記録を消せない: \(error)")
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(summaries) { summary in
                    NavigationLink(value: Route.record(recordId: summary.record.id!)) {
                        HistoryRow(summary: summary, showsTime: summary.record.sharesDay(with: summaries.map(\.record)))
                    }
                    .swipeActions {
                        // destructive にすると、確認の前に行を消すアニメーションが走る
                        Button("削除") { deleting = summary }
                            .tint(.red)
                    }
                    .contextMenu {
                        Section(Format.date(summary.record.performedAt, timeZone: summary.record.timeZone, weekday: true) + " の記録") {
                            Button("削除", systemImage: "trash", role: .destructive) { deleting = summary }
                        }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("新しい記録", systemImage: "plus") {
                    path.append(.newRecord(exerciseId: exerciseId, token: UUID()))
                }
                Button("種目の設定", systemImage: "gearshape") { isEditingExercise = true }
            }
        }
        .sheet(isPresented: $isEditingExercise) {
            if let exercise {
                ExerciseFormView(exercise: exercise)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible, presenting: deleting) { summary in
            Button("記録を削除", role: .destructive) { delete(summary.record) }
        } message: { summary in
            Text("セット \(summary.sets.count) 個" + (summary.record.memo.isEmpty ? "" : "とメモ") + "が消えます。元に戻せません。")
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
