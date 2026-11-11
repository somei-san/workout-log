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
        /// 1〜10 の外は未入力として扱う
        var rpeValue: Double? { Double(rpe).flatMap { (1...10).contains($0) ? $0 : nil } }
        /// 0 より小さい値は未入力として扱う
        var rirValue: Int? { Int(rir).flatMap { $0 >= 0 ? $0 : nil } }

        /// i 行目を消すと 1 回の記録ごと消えるか。保存したセットが、その行だけのとき
        static func deletesRecord(_ rows: [SetRow], at i: Int) -> Bool {
            rows[i].saved != nil && rows.filter { $0.saved != nil }.count == 1
        }

        /// 行を消した後の、残りのセット。順番を画面の行の順に詰め直す。後で足すセットと順番が重ならないようにするため
        static func renumbered(_ remaining: [SetRow]) -> [WorkoutSet] {
            remaining.enumerated().compactMap { index, row in
                row.saved.map { set -> WorkoutSet in
                    var set = set
                    set.position = index
                    return set
                }
            }
        }
    }

    private enum Field: Hashable {
        case weight(UUID), reps(UUID), intensity(UUID)

        var rowId: UUID {
            switch self {
            case .weight(let id), .reps(let id), .intensity(let id): id
            }
        }

        /// UI テストで欄を探す名前。重さと回数は、画面の並び順で 1 行に 2 つずつ並ぶものとして探す
        var accessibilityIdentifier: String {
            switch self {
            case .weight, .reps: "重さと回数"
            case .intensity: "強度"
            }
        }
    }

    let target: Target

    @Environment(\.appDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.intensity) private var intensity = IntensityKind.initial
    @State private var model = RecordModel()
    @State private var isChoosingDate = false
    @State private var isConfirmingRecordDelete = false
    @FocusState private var focus: Field?
    @FocusState private var isMemoFocused: Bool
    @State private var isKeyboardShown = false
    private let memoId = "memo"
    /// 欄の最小の幅。重さは「102.5」、回数は 1 桁が収まる幅。RPE は押しやすいよう 44pt 取る。文字の大きさの設定に合わせて広げる。
    /// 重さは行ごとに数字の右端がそろうよう広めに取り、回数は「×」と数字が離れないよう狭く取る
    @ScaledMetric(relativeTo: .title2) private var weightWidth: CGFloat = 66
    @ScaledMetric(relativeTo: .title2) private var repsWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var intensityWidth: CGFloat = 44

    var body: some View {
        ScrollViewReader { proxy in
            list
                // メモの欄は、欄に入ってもリストが送らず、キーボードに隠れる。キーボードが出たら、ボタンの並びの余白の上まで自分で送る。
                // 数字の欄からメモへ移るときはキーボードが出たままで、出たときの通知が来ないことがあるので、大きさが変わったときと欄に入ったときにも送る
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    scrollToMemo(proxy)
                }
                .onChange(of: isMemoFocused) { scrollToMemo(proxy) }
                .onChange(of: model.memo) { scrollToMemo(proxy) }
        }
    }

    private func scrollToMemo(_ proxy: ScrollViewProxy) {
        guard isMemoFocused else { return }
        withAnimation { proxy.scrollTo(memoId, anchor: .bottom) }
    }

    private var list: some View {
        List {
            Section {
                Text("前回  " + model.previousText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                    if model.isEditing {
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
                        viewRow(model.rows[..<i].filter { $0.saved != nil }.count + 1, set)
                    }
                }
                if model.isEditing {
                    Button("＋ セットを追加", action: addRow)
                        .frame(minHeight: 44)
                        .listRowSeparator(.hidden)
                }
            }
            Section("メモ") {
                if model.isEditing {
                    TextField("メモ", text: $model.memo, axis: .vertical)
                        .cursorHiddenInUITests()
                        .focused($isMemoFocused)
                        .id(memoId)
                        .onChange(of: model.memo) { model.saveMemo() }
                } else {
                    Text(model.memo)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(model.exercise?.name ?? "").font(.headline)
                    if model.isEditing {
                        Button { isChoosingDate = true } label: {
                            Text(dateText + " ▾")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityHint("日付と時刻を変える")
                    } else {
                        Text(dateText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if model.isPast {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isEditing ? "完了" : "編集") {
                        focus = nil
                        model.isEditing.toggle()
                    }
                }
            }
        }
        // キーボードの上のボタンは、OS のキーボードのツールバーではなく画面の下に置く。
        // ツールバーはキーボードにくっついて浮き、OS が打っている欄をツールバーの裏まで送るため、欄が隠れる。
        // 画面の下に置くと、打っている欄はボタンの並びと余白のさらに上まで送られる
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardShown && model.isEditing {
                keyboardBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
        }
        .dismissesKeyboardOnTapOutside()
        .sheet(isPresented: $isChoosingDate) {
            DateTimeSheet(date: model.performedAt, timeZone: model.record?.timeZone ?? .current) { date in
                model.changeDate(date)
                Task { await model.loadContext() }
            }
        }
        .confirmationDialog("記録を削除", isPresented: $isConfirmingRecordDelete, titleVisibility: .visible) {
            Button("記録を削除", role: .destructive) {
                if model.deleteRecord() { dismiss() }
            }
        } message: {
            Text("最後のセットを消すと、この記録ごと消えます。元に戻せません。")
        }
        .task {
            do {
                try await model.load(target, database: database)
            } catch {
                print("種目の記録を読めない: \(error)")
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // 数字の欄に入ったら、カーソルを数字の一番右に置く。⌫ で右から消せるようにするため。
            // 右寄せの欄の、数字より左の空いたところを押すと、カーソルが一番左に来てしまう。
            // 押した位置にカーソルを置くのは欄に入った後なので、次の描画まで待ってから動かす
            guard let textField = note.object as? UITextField,
                  [.decimalPad, .numberPad].contains(textField.keyboardType) else { return }
            Task { @MainActor in
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
            }
        }
        .onChange(of: focus) { old, new in
            if let old, old.rowId != new?.rowId {
                model.restoreIfCleared(old.rowId)
            }
        }
    }

    /// 左に打つもの（重さ × 回数）、右に添えるもの（RPE か RIR と 1RM）を置く
    private func editRow(_ i: Int, _ row: SetRow) -> some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                setNumber(i + 1)
                numberField(.weight(row.id), binding(row.id, \.weight), keyboard: .decimalPad, width: weightWidth)
                    .font(.title2)
                    .onChange(of: row.weight) { model.removeDisallowed(row.id, \.weight, filter: NumberInput.decimal) }
                unit("kg")
                times
                numberField(.reps(row.id), binding(row.id, \.reps), keyboard: .numberPad, width: repsWidth)
                    .font(.title2)
                    .onChange(of: row.reps) { model.removeDisallowed(row.id, \.reps, filter: NumberInput.integer) }
                unit("回")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if intensity != .none {
                    let (keyPath, filter) = intensity == .rpe
                        ? (\SetRow.rpe, NumberInput.decimal) : (\SetRow.rir, NumberInput.integer)
                    HStack(spacing: 2) {
                        unit(intensity.label)
                        numberField(.intensity(row.id), binding(row.id, keyPath),
                                    keyboard: intensity == .rpe ? .decimalPad : .numberPad, width: intensityWidth, alignment: .center)
                            .font(.subheadline)
                            .onChange(of: row[keyPath: keyPath]) { model.removeDisallowed(row.id, keyPath, filter: filter) }
                    }
                }
                Text("1RM " + estimated1RMText(row))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 60)
    }

    private func viewRow(_ number: Int, _ set: WorkoutSet) -> some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                setNumber(number)
                Text(Format.weight(set.weight))
                    .font(.title2)
                    .monospacedDigit()
                    .frame(minWidth: weightWidth, alignment: .trailing)
                unit("kg")
                times
                Text("\(set.reps)")
                    .font(.title2)
                    .monospacedDigit()
                    .frame(minWidth: repsWidth, alignment: .trailing)
                unit("回")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let value = intensity == .rpe ? set.rpe.map(Format.weight) : intensity == .rir ? set.rir.map(String.init) : nil {
                    Text("\(intensity.label) \(value)").font(.subheadline)
                }
                Text("1RM " + Format.weight((set.estimated1RM * 10).rounded() / 10) + "kg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 60)
    }

    /// 数字の欄。欄の幅を数字の桁に合わせ、重さ × 回数が 1 つの塊に見えるようにする。
    /// 見た目は数字だけだが、押せる高さは 44pt 取る。打っている欄は数字の色で分かるようにする
    private func numberField(_ field: Field, _ text: Binding<String>, keyboard: UIKeyboardType, width: CGFloat,
                             alignment: TextAlignment = .trailing) -> some View {
        // 欄の幅は、見えない Text で打った数字の幅を測って決め、width より狭くはしない。
        // TextField に fixedSize を付けて縮めると、空の欄が「–」の幅になり、
        // カーソルが見えず、押してもキーボードが出ないことがある
        Text(text.wrappedValue.isEmpty ? "–" : text.wrappedValue)
            .monospacedDigit()
            .hidden()
            .frame(minWidth: width)
            .overlay {
                // 入力中の欄では、空でもカーソルだけを出す。中央寄せの空の欄で「–」を出すと、
                // カーソルが「–」の左に離れて出た。幅は上の Text が「–」で測るので変わらない
                TextField(focus == field ? "" : "–", text: text)
                    .keyboardType(keyboard)
                    .focused($focus, equals: field)
                    .multilineTextAlignment(alignment)
                    .monospacedDigit()
                    .foregroundStyle(focus == field ? Color.accentColor : .primary)
                    .cursorHiddenInUITests()
                    .accessibilityIdentifier(field.accessibilityIdentifier)
            }
            .frame(minHeight: 44)
            // 欄の上下の余白を押しても、その欄に入るようにする
            .background { Color.clear.contentShape(.rect).onTapGesture { focus = field } }
    }

    /// キーボードのすぐ上に出すボタンの並び。打っている欄に効くボタンだけを出す。
    /// メモではボタンを出さず、余白だけを取る。打っている行がキーボードにくっつかないようにするため
    private var keyboardBar: some View {
        VStack(spacing: 0) {
            if let focus {
                HStack(spacing: 8) {
                    switch focus {
                    case .weight:
                        Button("前回と同じ", action: copyWeightAbove)
                            .disabled(rowAbove?.weightValue == nil)
                        Button("−2.5") { adjustWeight(-2.5) }
                        Button("＋2.5") { adjustWeight(2.5) }
                    case .reps:
                        Button("前回と同じ", action: copyRepsAbove)
                            .disabled(rowAbove?.repsValue == nil)
                        Button("−1") { adjustReps(-1) }
                        Button("＋1") { adjustReps(1) }
                    case .intensity:
                        EmptyView()
                    }
                    Spacer()
                    Button("次へ", action: moveToNextField)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(8)
                .background(.regularMaterial, in: .capsule)
                .keepsKeyboardOnTap()
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func setNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: 20, alignment: .leading)
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private var times: some View {
        Text("×").font(.footnote).foregroundStyle(.tertiary).padding(.horizontal, 4)
    }

    private var dateText: String {
        Format.date(model.performedAt, timeZone: model.record?.timeZone ?? .current, weekday: true, time: model.sharesDay)
    }

    private func estimated1RMText(_ row: SetRow) -> String {
        guard let weight = row.weightValue, let reps = row.repsValue else { return "–" }
        let value = WorkoutSet(recordId: 0, position: 0, weight: weight, reps: reps).estimated1RM
        return Format.weight((value * 10).rounded() / 10) + "kg"
    }

    private func binding(_ rowId: UUID, _ keyPath: WritableKeyPath<SetRow, String>) -> Binding<String> {
        Binding {
            model.value(rowId, keyPath)
        } set: { value in
            model.setValue(rowId, keyPath, value)
        }
    }

    // MARK: - 編集

    private func addRow() {
        focus = .weight(model.addRow())
    }

    private func adjustWeight(_ delta: Double) {
        guard let focus else { return }
        model.adjustWeight(focus.rowId, by: delta)
    }

    private func adjustReps(_ delta: Int) {
        guard let focus else { return }
        model.adjustReps(focus.rowId, by: delta)
    }

    /// 写したら次の欄へ移る。前回と同じ値なら、その欄で打つものは無いため
    private func copyWeightAbove() {
        guard let focus, model.copyWeightAbove(focus.rowId) else { return }
        moveToNextField()
    }

    private func copyRepsAbove() {
        guard let focus, model.copyRepsAbove(focus.rowId) else { return }
        moveToNextField()
    }

    /// 重さ → 回数 → 強度（出しているときだけ）→ 次の行の重さ、の順に次の欄へ移る。
    /// 最後の行の最後の欄では、空の行を足して、その行の重さへ移る。セットを続けて打つときに、欄を押し直さずに済むようにするため
    private func moveToNextField() {
        guard let focus, let i = model.index(of: focus.rowId) else { return }
        switch focus {
        case .weight(let id):
            self.focus = .reps(id)
        case .reps(let id) where intensity != .none:
            self.focus = .intensity(id)
        case .reps, .intensity:
            if i + 1 < model.rows.count {
                self.focus = .weight(model.rows[i + 1].id)
            } else {
                addRow()
            }
        }
    }

    /// 打っている行の 1 つ上の行
    private var rowAbove: SetRow? {
        focus.flatMap { model.rowAbove($0.rowId) }
    }

    /// 行を消す。最後のセットのときは記録ごと消えるので、消さずに確認を出す
    private func deleteRow(_ rowId: UUID) {
        guard model.index(of: rowId) != nil else { return }
        focus = nil
        if model.deleteRow(rowId) == .needsConfirmation {
            isConfirmingRecordDelete = true
        }
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
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Clock.now()))!
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
