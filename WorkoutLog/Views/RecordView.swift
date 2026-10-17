import GRDB
import SwiftUI

/// 種目の記録(編集モード)
struct RecordView: View {
    enum Target: Hashable {
        case existing(recordId: Int64)
        case new(exerciseId: Int64)
    }

    /// 画面の行。重さと回数が入るとセットとして保存する。空の行は保存しない
    struct SetRow: Identifiable {
        let id = UUID()
        /// 保存したセット。重さか回数を消して行を離れたときに、この値に戻す
        var saved: WorkoutSet?
        var weight = ""
        var reps = ""
        var rpe = ""
        var rir = ""

        var weightValue: Double? { Double(weight).flatMap { $0 >= 0 ? $0 : nil } }
        var repsValue: Int? { Int(reps).flatMap { $0 > 0 ? $0 : nil } }
        var isFilled: Bool { weightValue != nil && repsValue != nil }
    }

    private enum Field: Hashable {
        case weight(UUID), reps(UUID), intensity(UUID)

        var rowId: UUID {
            switch self {
            case .weight(let id), .reps(let id), .intensity(let id): id
            }
        }
    }

    let target: Target

    @Environment(\.appDatabase) private var database
    @AppStorage("intensity") private var intensity = IntensityKind.rpe
    @State private var exercise: Exercise?
    /// 保存した 1 回の記録。新しい記録では、最初のセットができるまで nil
    @State private var record: WorkoutRecord?
    @State private var openedAt = Date()
    @State private var rows: [SetRow] = []
    @State private var memo = ""
    @State private var previousSets: [WorkoutSet]?
    @State private var sharesDay = false
    @State private var isLoaded = false
    @FocusState private var focus: Field?

    var body: some View {
        List {
            Section {
                Text("前回  " + previousText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    rowView(i, row)
                }
                Button(action: addRow) {
                    Image(systemName: "plus")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.green, in: .circle)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("行を足す")
                .listRowSeparator(.hidden)
            }
            Section("メモ") {
                TextField("", text: $memo, axis: .vertical)
                    .onChange(of: memo) { saveMemo() }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(exercise?.name ?? "").font(.headline)
                    Text(dateText).font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button("−2.5") { adjustWeight(-2.5) }
                Button("＋2.5") { adjustWeight(2.5) }
                Spacer()
                Button("−1") { adjustReps(-1) }
                Button("＋1") { adjustReps(1) }
                Spacer()
                Button("閉じる") { focus = nil }
            }
        }
        .task { await load() }
        .onChange(of: focus) { old, new in
            if let old, old.rowId != new?.rowId {
                restoreIfCleared(old.rowId)
            }
        }
    }

    /// 保存したセットの重さか回数を消したまま行を離れたら、保存した値に戻す
    private func restoreIfCleared(_ rowId: UUID) {
        // 空の行は保存しないので、消した値はデータベースに届かず、戻さないと表示とずれる
        guard let i = rows.firstIndex(where: { $0.id == rowId }), let saved = rows[i].saved, !rows[i].isFilled else { return }
        rows[i].weight = Format.weight(saved.weight)
        rows[i].reps = String(saved.reps)
    }

    private func rowView(_ i: Int, _ row: SetRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(i + 1)")
                    .frame(width: 24, alignment: .leading)
                TextField("–", text: binding(i, \.weight))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .weight(row.id))
                    .multilineTextAlignment(.trailing)
                    .font(.title3.bold())
                Text("kg").font(.caption)
                TextField("–", text: binding(i, \.reps))
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .reps(row.id))
                    .multilineTextAlignment(.trailing)
                    .font(.title3.bold())
                Text("回").font(.caption)
            }
            HStack {
                Text("1RM " + (row.isFilled ? Format.weight(estimated1RM(row)) + "kg" : "–"))
                Spacer()
                if intensity != .none {
                    Text(intensity.label)
                    TextField("", text: binding(i, intensity == .rpe ? \.rpe : \.rir))
                        .keyboardType(intensity == .rpe ? .decimalPad : .numberPad)
                        .focused($focus, equals: .intensity(row.id))
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 6))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 24)
        }
        .frame(minHeight: 56)
    }

    private var previousText: String {
        guard let previousSets else { return "" }
        return previousSets.isEmpty ? "なし" : Format.sets(previousSets)
    }

    private var dateText: String {
        let at = record?.performedAt ?? openedAt
        return Format.date(at, timeZone: record?.timeZone ?? .current, weekday: true, time: sharesDay)
    }

    private func estimated1RM(_ row: SetRow) -> Double {
        let value = WorkoutSet(recordId: 0, position: 0, weight: row.weightValue ?? 0, reps: row.repsValue ?? 0).estimated1RM
        return (value * 10).rounded() / 10
    }

    private func binding(_ i: Int, _ keyPath: WritableKeyPath<SetRow, String>) -> Binding<String> {
        Binding {
            rows.indices.contains(i) ? rows[i][keyPath: keyPath] : ""
        } set: { value in
            guard rows.indices.contains(i), rows[i][keyPath: keyPath] != value else { return }
            rows[i][keyPath: keyPath] = value
            persist(i)
        }
    }

    // MARK: - 読み込み

    private struct Loaded: Sendable {
        var exercise: Exercise
        var record: WorkoutRecord?
        var sets: [WorkoutSet]
        var previousSets: [WorkoutSet]
        var sharesDay: Bool
    }

    private func load() async {
        guard !isLoaded else { return }
        isLoaded = true
        let target = target, openedAt = openedAt
        do {
            let loaded = try await database.reader.read { db -> Loaded in
                switch target {
                case .existing(let recordId):
                    let record = try WorkoutRecord.fetchOne(db, id: recordId)!
                    return Loaded(
                        exercise: try Exercise.fetchOne(db, id: record.exerciseId)!,
                        record: record,
                        sets: try record.fetchSets(db),
                        previousSets: try record.previous(db)?.fetchSets(db) ?? [],
                        sharesDay: try record.sharesDay(db))
                case .new(let exerciseId):
                    let draft = WorkoutRecord(exerciseId: exerciseId, performedAt: openedAt)
                    return Loaded(
                        exercise: try Exercise.fetchOne(db, id: exerciseId)!,
                        record: nil,
                        sets: [],
                        previousSets: try draft.previous(db)?.fetchSets(db) ?? [],
                        sharesDay: try draft.sharesDay(db))
                }
            }
            exercise = loaded.exercise
            record = loaded.record
            memo = loaded.record?.memo ?? ""
            previousSets = loaded.previousSets
            sharesDay = loaded.sharesDay
            rows = loaded.record == nil
                ? Array(repeating: (), count: loaded.exercise.initialRowCount).map { SetRow() }
                : loaded.sets.map { set in
                    SetRow(saved: set, weight: Format.weight(set.weight), reps: String(set.reps),
                           rpe: set.rpe.map(Format.weight) ?? "", rir: set.rir.map(String.init) ?? "")
                }
        } catch {
            print("種目の記録を読めない: \(error)")
        }
    }

    // MARK: - 編集

    /// 「＋」で足す行には、直前のセットの値を入れる。セットが無ければ前回の 1 セット目、前回も無ければ空の行
    private func addRow() {
        var row = SetRow()
        if let last = rows.last(where: \.isFilled) {
            row.weight = last.weight
            row.reps = last.reps
        } else if let first = previousSets?.first {
            row.weight = Format.weight(first.weight)
            row.reps = String(first.reps)
        }
        rows.append(row)
        if row.isFilled {
            persist(rows.count - 1)
        } else {
            focus = .weight(row.id)
        }
    }

    private func adjustWeight(_ delta: Double) {
        guard let i = focusedIndex else { return }
        rows[i].weight = Format.weight(max(0, (rows[i].weightValue ?? 0) + delta))
        persist(i)
    }

    private func adjustReps(_ delta: Int) {
        guard let i = focusedIndex else { return }
        rows[i].reps = String(max(1, (rows[i].repsValue ?? 0) + delta))
        persist(i)
    }

    private var focusedIndex: Int? {
        guard let focus else { return nil }
        return rows.firstIndex { $0.id == focus.rowId }
    }

    /// 行を保存する。重さと回数がそろっていない行は保存しない。
    /// 新しい記録では、最初のセットを保存するときに 1 回の記録も作る
    private func persist(_ i: Int) {
        let row = rows[i]
        guard let weight = row.weightValue, let reps = row.repsValue, let exerciseId = exercise?.id else { return }
        let record = record, memo = memo
        // RPE は 1〜10、RIR は 0 以上。範囲の外は未入力として扱う
        let rpe = Double(row.rpe).flatMap { (1...10).contains($0) ? $0 : nil }
        let rir = Int(row.rir).flatMap { $0 >= 0 ? $0 : nil }
        do {
            let (savedRecord, savedSet) = try database.writer.write { db in
                var record = record ?? WorkoutRecord(exerciseId: exerciseId, performedAt: Date(), memo: memo)
                if record.id == nil {
                    try record.insert(db)
                }
                var set = WorkoutSet(id: row.saved?.id, recordId: record.id!, position: i, weight: weight, reps: reps, rpe: rpe, rir: rir)
                try set.save(db)
                return (record, set)
            }
            self.record = savedRecord
            rows[i].saved = savedSet
        } catch {
            print("セットを保存できない: \(error)")
        }
    }

    private func saveMemo() {
        guard var record, record.memo != memo else { return }
        record.memo = memo
        do {
            try database.writer.write { db in try record.update(db) }
            self.record = record
        } catch {
            print("メモを保存できない: \(error)")
        }
    }
}
