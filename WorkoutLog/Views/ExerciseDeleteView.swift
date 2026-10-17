import GRDB
import SwiftUI

/// 種目の削除。記録もすべて消えて元に戻せないので、「削除」と入力させてから消す
struct ExerciseDeleteView: View {
    let exercise: Exercise

    @Environment(\.appDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var recordCount = 0
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(exercise.name)
                        .font(.title2.bold())
                    Text("この種目の記録 \(recordCount) 回分と、そのメモがすべて消えます。\n消した記録は元に戻せません。")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.4)))
                    Text("記録を残したまま一覧から外すときは、削除ではなく「非表示」を使う。")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("確認のため「削除」と入力してください")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("", text: $confirmation)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    Button(role: .destructive, action: delete) {
                        Text("この種目を削除する")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(confirmation != "削除")
                }
                .padding()
            }
            .navigationTitle("種目を削除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .task {
            guard let id = exercise.id else { return }
            recordCount = (try? await database.reader.read { db in
                try WorkoutRecord.filter(Column("exerciseId") == id).fetchCount(db)
            }) ?? 0
        }
    }

    private func delete() {
        do {
            _ = try database.writer.write { db in try exercise.delete(db) }
            dismiss()
        } catch {
            print("種目を消せない: \(error)")
        }
    }
}
