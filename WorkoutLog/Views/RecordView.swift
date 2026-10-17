import GRDB
import SwiftUI

/// 種目の記録。今日の記録と新しい記録は編集モード、前日以前の記録は閲覧モードで開く
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.intensity) private var intensity = IntensityKind.initial
    @State private var exercise: Exercise?
    /// 保存した 1 回の記録。新しい記録では、最初のセットができるまで nil
    @State private var record: WorkoutRecord?
    /// 新しい記録で、最初のセットの前に選んだ日付と時刻
    @State private var chosenAt: Date?
    @State private var openedAt = Date()
    @State private var rows: [SetRow] = []
    @State private var memo = ""
    @State private var previousSets: [WorkoutSet]?
    @State private var sharesDay = false
    @State private var isLoaded = false
    @State private var isEditing = true
    /// 前日以前の記録。閲覧モードで開く
    @State private var isPast = false
    @State private var isChoosingDate = false
    @State private var isConfirmingRecordDelete = false
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
                    if isEditing {
                        editRow(i, row)
                            .swipeActions {
                                // destructive にすると、最後のセットで確認を出す前に行を消すアニメーションが走る
                                Button("削除") { deleteRow(row.id) }
                                    .tint(.red)
                            }
                            .contextMenu {
                                Section("\(i + 1) セット目") {
                                    Button("削除", systemImage: "trash", role: .destructive) { deleteRow(row.id) }
                                }
                            }
                    } else if let set = row.saved {
                        // 閲覧モードは空の行を出さないので、番号はセットだけで数える
                        viewRow(rows[..<i].filter { $0.saved != nil }.count + 1, set)
                    }
                }
                if isEditing {
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
            }
            Section("メモ") {
                if isEditing {
                    TextField("", text: $memo, axis: .vertical)
                        .onChange(of: memo) { saveMemo() }
                } else {
                    Text(memo)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(exercise?.name ?? "").font(.headline)
                    if isEditing {
                        Button { isChoosingDate = true } label: {
                            Text(dateText + " ▾")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityHint("日付と時刻を変える")
                    } else {
                        Text(dateText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if isPast {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "完了" : "編集") {
                        focus = nil
                        isEditing.toggle()
                    }
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
        .sheet(isPresented: $isChoosingDate) {
            DateTimeSheet(date: performedAt, timeZone: record?.timeZone ?? .current, onDone: changeDate)
        }
        .confirmationDialog("記録を削除", isPresented: $isConfirmingRecordDelete, titleVisibility: .visible) {
            Button("記録を削除", role: .destructive, action: deleteRecord)
        } message: {
            Text("最後のセットを消すと、この記録ごと消えます。元に戻せません。")
        }
        .task { await load() }
        .onChange(of: focus) { old, new in
            if let old, old.rowId != new?.rowId {
                restoreIfCleared(old.rowId)
            }
        }
    }

    private func editRow(_ i: Int, _ row: SetRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(i + 1)")
                    .frame(width: 24, alignment: .leading)
                TextField("–", text: binding(row.id, \.weight))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .weight(row.id))
                    .multilineTextAlignment(.trailing)
                    .font(.title3.bold())
                Text("kg").font(.caption)
                TextField("–", text: binding(row.id, \.reps))
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .reps(row.id))
                    .multilineTextAlignment(.trailing)
                    .font(.title3.bold())
                Text("回").font(.caption)
            }
            HStack {
                Text("1RM " + estimated1RMText(row))
                Spacer()
                if intensity != .none {
                    Text(intensity.label)
                    TextField("", text: binding(row.id, intensity == .rpe ? \.rpe : \.rir))
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

    private func viewRow(_ number: Int, _ set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(number)")
                    .frame(width: 24, alignment: .leading)
                Text(Format.weight(set.weight)).font(.title3.bold())
                Text("kg ×").font(.caption)
                Text("\(set.reps)").font(.title3.bold())
                Text("回").font(.caption)
                Spacer()
                if let value = intensity == .rpe ? set.rpe.map(Format.weight) : intensity == .rir ? set.rir.map(String.init) : nil {
                    Text("\(intensity.label) \(value)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("1RM " + Format.weight((set.estimated1RM * 10).rounded() / 10) + "kg")
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

    private var performedAt: Date {
        record?.performedAt ?? chosenAt ?? openedAt
    }

    private var dateText: String {
        Format.date(performedAt, timeZone: record?.timeZone ?? .current, weekday: true, time: sharesDay)
    }

    private func estimated1RMText(_ row: SetRow) -> String {
        guard let weight = row.weightValue, let reps = row.repsValue else { return "–" }
        let value = WorkoutSet(recordId: 0, position: 0, weight: weight, reps: reps).estimated1RM
        return Format.weight((value * 10).rounded() / 10) + "kg"
    }

    private func binding(_ rowId: UUID, _ keyPath: WritableKeyPath<SetRow, String>) -> Binding<String> {
        Binding {
            rows.first { $0.id == rowId }?[keyPath: keyPath] ?? ""
        } set: { value in
            guard let i = rows.firstIndex(where: { $0.id == rowId }), rows[i][keyPath: keyPath] != value else { return }
            rows[i][keyPath: keyPath] = value
            persist(i)
        }
    }

    // MARK: - 読み込み

    private struct Loaded: Sendable {
        var exercise: Exercise
        var record: WorkoutRecord?
        var sets: [WorkoutSet]
    }

    private func load() async {
        guard !isLoaded else { return }
        isLoaded = true
        let target = target
        do {
            let loaded = try await database.reader.read { db -> Loaded in
                switch target {
                case .existing(let recordId):
                    guard let record = try WorkoutRecord.fetchOne(db, id: recordId),
                          let exercise = try Exercise.fetchOne(db, id: record.exerciseId)
                    else { throw RecordError.notFound }
                    return Loaded(exercise: exercise, record: record, sets: try record.fetchSets(db))
                case .new(let exerciseId):
                    guard let exercise = try Exercise.fetchOne(db, id: exerciseId) else { throw RecordError.notFound }
                    return Loaded(exercise: exercise, record: nil, sets: [])
                }
            }
            exercise = loaded.exercise
            record = loaded.record
            memo = loaded.record?.memo ?? ""
            isPast = loaded.record.map { $0.day < LocalDay.today() } ?? false
            isEditing = !isPast
            rows = loaded.record == nil
                ? (0..<loaded.exercise.initialRowCount).map { _ in SetRow() }
                : loaded.sets.map { set in
                    SetRow(saved: set, weight: Format.weight(set.weight), reps: String(set.reps),
                           rpe: set.rpe.map(Format.weight) ?? "", rir: set.rir.map(String.init) ?? "")
                }
            await loadContext()
        } catch {
            print("種目の記録を読めない: \(error)")
            dismiss()
        }
    }

    /// 前回と、同じ日に別の記録があるか。日付と時刻を変えると変わるので、変えるたびに読み直す
    private func loadContext() async {
        guard let exerciseId = exercise?.id else { return }
        let current = record ?? WorkoutRecord(exerciseId: exerciseId, performedAt: performedAt)
        do {
            let (previous, shares) = try await database.reader.read { db in
                (try current.previous(db)?.fetchSets(db) ?? [], try current.sharesDay(db))
            }
            previousSets = previous
            sharesDay = shares
        } catch {
            print("前回を読めない: \(error)")
        }
    }

    private enum RecordError: Error {
        case notFound
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
        let record = record, memo = memo, performedAt = chosenAt ?? Date()
        // RPE は 1〜10、RIR は 0 以上。範囲の外は未入力として扱う
        let rpe = Double(row.rpe).flatMap { (1...10).contains($0) ? $0 : nil }
        let rir = Int(row.rir).flatMap { $0 >= 0 ? $0 : nil }
        do {
            let (savedRecord, savedSet) = try database.writer.write { db in
                var record = record ?? WorkoutRecord(exerciseId: exerciseId, performedAt: performedAt, memo: memo)
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

    /// 保存したセットの重さか回数を消したまま行を離れたら、保存した値に戻す
    private func restoreIfCleared(_ rowId: UUID) {
        // 空の行は保存しないので、消した値はデータベースに届かず、戻さないと表示とずれる
        guard let i = rows.firstIndex(where: { $0.id == rowId }), let saved = rows[i].saved, !rows[i].isFilled else { return }
        rows[i].weight = Format.weight(saved.weight)
        rows[i].reps = String(saved.reps)
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

    /// 行を消す。最後のセットのときは記録ごと消えるので、消さずに確認を出す
    private func deleteRow(_ rowId: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == rowId }) else { return }
        focus = nil
        if rows[i].saved != nil, rows.filter({ $0.saved != nil }).count == 1 {
            isConfirmingRecordDelete = true
            return
        }
        var remaining = rows
        remaining.remove(at: i)
        let deleted = rows[i].saved
        // 残りのセットの順番を、画面の行の順に詰め直す。後で足すセットと順番が重ならないようにするため
        let renumbered = remaining.enumerated().compactMap { index, row in
            row.saved.map { set -> WorkoutSet in
                var set = set
                set.position = index
                return set
            }
        }
        do {
            try database.writer.write { db in
                if let deleted {
                    _ = try deleted.delete(db)
                }
                for set in renumbered {
                    try set.update(db)
                }
            }
            rows = remaining
            for set in renumbered {
                if let index = rows.firstIndex(where: { $0.saved?.id == set.id }) {
                    rows[index].saved = set
                }
            }
        } catch {
            print("セットを消せない: \(error)")
        }
    }

    private func deleteRecord() {
        guard let record else { return }
        do {
            _ = try database.writer.write { db in try record.delete(db) }
            dismiss()
        } catch {
            print("記録を消せない: \(error)")
        }
    }

    /// 日付と時刻を変える。保存した記録は、記録した場所の時刻のまま変える(utcOffset は変えない)。
    /// 今の端末のタイムゾーンで書き直すと、別のタイムゾーンで開いて変えたときに、記録の日付がずれるため。
    /// 新しい記録で最初のセットの前なら、選んだ値を覚えておき、最初のセットを保存するときに使う
    private func changeDate(_ date: Date) {
        if var record {
            record.performedAt = date
            do {
                try database.writer.write { db in try record.update(db) }
                self.record = record
            } catch {
                print("日付と時刻を変えられない: \(error)")
            }
        } else {
            chosenAt = date
        }
        Task { await loadContext() }
    }
}

/// 日付と時刻を選ぶシート。記録した場所のタイムゾーンで選ぶ。今日より後の日は選べない
private struct DateTimeSheet: View {
    @State var date: Date
    let timeZone: TimeZone
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 今日の終わり。今日のうちなら、今より後の時刻も選べる
    private var endOfToday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        return tomorrow.addingTimeInterval(-1)
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("日付", selection: $date, in: ...endOfToday, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                DatePicker("時刻", selection: $date, in: ...endOfToday, displayedComponents: .hourAndMinute)
                Spacer()
            }
            .padding()
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.timeZone, timeZone)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onDone(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
