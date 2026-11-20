import SwiftUI

/// 種目の追加と種目の設定。id の無い種目を渡すと追加になる
struct ExerciseFormView: View {
    @Environment(\.appDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State var exercise: Exercise
    @AppStorage(SettingsKey.partOrder) private var partOrder = ""

    private var isNew: Bool { exercise.id == nil }
    private var trimmedName: String { exercise.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: ベンチプレス", text: $exercise.name)
                        .cursorHiddenInUITests()
                }
                Section("部位") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PartOrder.decode(partOrder), id: \.self) { part in
                            let isSelected = exercise.part == part
                            Button {
                                exercise.part = part
                            } label: {
                                HStack(spacing: 8) {
                                    // 横に部位の名前を出すので、アイコンの名前は読み上げない
                                    PartIcon(part: part)
                                        .accessibilityHidden(true)
                                    Text(part.label)
                                        .fontWeight(isSelected ? .bold : .regular)
                                    Spacer(minLength: 0)
                                    if isSelected {
                                        // 選んでいることは、ボタンに付けた選択中の状態（accessibilityAddTraits）で読み上げる
                                        Image(systemName: "checkmark")
                                            .fontWeight(.bold)
                                            .foregroundStyle(part.color)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 52)
                                // ダークでは背景が暗く、薄い色が沈むので、部位のアイコンの丸と同じく地を濃くする
                                .background(isSelected ? AnyShapeStyle(part.color.opacity(colorScheme == .dark ? 0.28 : 0.16))
                                                       : AnyShapeStyle(Color(.secondarySystemBackground)),
                                            in: .rect(cornerRadius: 10))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 10).stroke(part.color, lineWidth: 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(exercise.part == part ? .isSelected : [])
                        }
                    }
                }
                Section("最初に並べるセット数") {
                    Stepper("空の行の数  \(exercise.initialRowCount)", value: $exercise.initialRowCount, in: 0...10)
                }
            }
            .navigationTitle(isNew ? "種目を追加" : "種目の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        var exercise = exercise
        exercise.name = trimmedName
        do {
            try database.writer.write { db in try exercise.save(db) }
            dismiss()
        } catch {
            print("種目を保存できない: \(error)")
        }
    }
}
