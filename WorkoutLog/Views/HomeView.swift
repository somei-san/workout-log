import GRDB
import SwiftUI

/// 種目(ホーム)
struct HomeView: View {
    enum Mode: String {
        case all, part
    }

    @Environment(\.appDatabase) private var database
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("home.mode") private var mode = Mode.all
    /// 並べ方は見方ごとに覚えておく
    @AppStorage("home.sort.all") private var sortAll = SortRule.elapsedDesc
    @AppStorage("home.sort.part") private var sortPart = SortRule.elapsedDesc
    @AppStorage(SettingsKey.partOrder) private var partOrder = ""
    /// 部位を並べ替えている間の状態。並べ替えていなければ nil
    @State private var reorder: PartReorder?
    /// 並べ替えの間、ドラッグが続いているか。ドラッグが終わるか取り消されると false に戻る
    @GestureState private var isReordering = false
    /// 並べ替えの間に出す部位の帯の高さ。文字の大きさの設定に合わせて変える
    @ScaledMetric private var bandHeight: CGFloat = 46
    /// 経過日数の基準。日をまたいでアプリに戻ったときに数え直すため、状態で持つ
    @State private var today = LocalDay.today()
    @State private var cards: [ExerciseCard] = []
    @State private var path: [Route] = []
    @State private var isAdding = false
    @State private var showsHidden = false
    @State private var editing: Exercise?
    @State private var deleting: Exercise?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let visible = rule.sorted(cards.filter { !$0.exercise.isHidden }, today: today)
                switch mode {
                case .all:
                    grid(visible)
                case .part:
                    let groups = Dictionary(grouping: visible, by: \.exercise.part)
                    let parts = PartOrder.decode(partOrder).filter { groups[$0] != nil }
                    ForEach(parts.indices, id: \.self) { i in
                        partSection(parts[i], groups[parts[i]]!, index: i, parts: parts, groups: groups)
                    }
                }
                let hidden = rule.sorted(cards.filter(\.exercise.isHidden), today: today)
                if !hidden.isEmpty {
                    DisclosureGroup("非表示の種目(\(hidden.count))", isExpanded: $showsHidden) {
                        grid(hidden)
                    }
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
            // 並べ替えの間は、種目のグリッドを隠し、部位の帯だけを上に並べる。
            // グリッドは消さずに透明にする。消すと、ドラッグを受けている部位の名前も消え、ドラッグが途切れるため
            .opacity(reorder == nil ? 1 : 0)
            .scrollDisabled(reorder != nil)
            .overlay {
                if let reorder {
                    PartReorderView(reorder: reorder)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: isReordering) {
                if !isReordering { finishReorder() }
            }
            .sensoryFeedback(.impact, trigger: reorder != nil) { _, isOn in isOn }
            // 始めたときと離したときは、入る位置が変わったのではないので振動しない
            .sensoryFeedback(.selection, trigger: reorder?.target) { old, new in old != nil && new != nil }
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("種目がありません", systemImage: "dumbbell", description: Text("右上の「＋」で種目を追加します"))
                }
            }
            .toolbar {
                // 切り替えは自分の枠を持つので、ツールバーの枠を重ねると二重に見える
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { modePicker }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { modePicker }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("並べ替え [\(mode == .all ? "すべて" : "部位")]", selection: mode == .all ? $sortAll : $sortPart) {
                            ForEach(SortRule.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("並べ替え", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Label("設定", systemImage: "gearshape")
                    }
                    Button("種目を追加", systemImage: "plus") { isAdding = true }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history(let exerciseId):
                    HistoryView(exerciseId: exerciseId, path: $path)
                case .record(let recordId):
                    RecordView(target: .existing(recordId: recordId))
                case .newRecord(let exerciseId, _):
                    RecordView(target: .new(exerciseId: exerciseId))
                case .analysis(let exerciseId):
                    AnalysisView(exerciseId: exerciseId)
                case .settings:
                    SettingsView()
                case .csvImport:
                    CSVImportView()
                }
            }
            .sheet(isPresented: $isAdding) {
                ExerciseFormView(exercise: Exercise(name: "", part: .chest))
            }
            .sheet(item: $editing) { exercise in
                ExerciseFormView(exercise: exercise)
            }
            .sheet(item: $deleting) { exercise in
                ExerciseDeleteView(exercise: exercise)
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { today = .today() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = .today()
        }
        .task(id: today) {
            let today = today
            let observation = ValueObservation.tracking { db in try ExerciseCard.fetchAll(db, today: today) }
            do {
                for try await value in observation.values(in: database.reader) {
                    cards = value
                }
            } catch {
                print("ホームの種目を読めない: \(error)")
            }
        }
    }

    private var modePicker: some View {
        Picker("見方", selection: $mode) {
            Text("すべて").tag(Mode.all)
            Text("部位").tag(Mode.part)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// 部位の名前と種目のグリッドをまとめた区切り。名前を長押しすると並べ替えを始める。
    /// parts と groups は、種目の無い部位を除いた、画面に出ている部位とその種目
    private func partSection(_ part: Part, _ cards: [ExerciseCard], index: Int, parts: [Part], groups: [Part: [ExerciseCard]]) -> some View {
        VStack {
            Text(part.label)
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                .contentShape(.rect)
                .gesture(reorderGesture(part, index: index, parts: parts, groups: groups))
                // ドラッグできない VoiceOver でも並べ替えられるようにする
                .accessibilityActions {
                    if index > 0 {
                        Button("前へ移動") { save(parts.moving(from: index, to: index - 1)) }
                    }
                    if index + 1 < parts.count {
                        Button("後ろへ移動") { save(parts.moving(from: index, to: index + 1)) }
                    }
                }
            grid(cards)
        }
    }

    /// 部位の名前を長押しして、そのまま上下にドラッグする操作
    private func reorderGesture(_ part: Part, index: Int, parts: [Part], groups: [Part: [ExerciseCard]]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isReordering) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if reorder == nil {
                    let bands = parts.map { PartReorder.Band(part: $0, names: groups[$0, default: []].map(\.exercise.name)) }
                    // 文字を大きくしても、7 部位の帯が 1 画面に収まる高さにとどめる
                    let height = min(bandHeight, 64)
                    withAnimation(.snappy) { reorder = PartReorder(bands: bands, held: part, start: index, bandHeight: height) }
                }
                guard let moved = drag?.translation.height, let target = reorder?.target(moved: moved) else { return }
                reorder?.moved = moved
                if target != reorder?.target {
                    withAnimation(.snappy) { reorder?.target = target }
                }
            }
    }

    private func finishReorder() {
        guard let reorder else { return }
        save(reorder.order)
        withAnimation(.snappy) { self.reorder = nil }
    }

    /// 画面に出ている部位の並びを、種目の無い部位を含む部位の並びに当てはめて保存する
    private func save(_ visible: [Part]) {
        partOrder = PartOrder.encode(PartOrder.applying(visible, to: PartOrder.decode(partOrder)))
    }

    private func grid(_ cards: [ExerciseCard]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(cards) { card in
                NavigationLink(value: Route.history(exerciseId: card.exercise.id!)) {
                    ExerciseCardView(card: card, today: today)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let exercise = card.exercise
                    Section(exercise.name) {
                        Button("種目の設定", systemImage: "gearshape") { editing = exercise }
                        if exercise.isHidden {
                            Button("再表示", systemImage: "eye") { setHidden(exercise, false) }
                        } else {
                            Button("非表示", systemImage: "eye.slash") { setHidden(exercise, true) }
                        }
                        Button("削除", systemImage: "trash", role: .destructive) { deleting = exercise }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func setHidden(_ exercise: Exercise, _ isHidden: Bool) {
        var exercise = exercise
        exercise.isHidden = isHidden
        do {
            try database.writer.write { db in try exercise.update(db) }
        } catch {
            print("種目を非表示にできない: \(error)")
        }
    }

    private var rule: SortRule { mode == .all ? sortAll : sortPart }
}

private struct ExerciseCardView: View {
    let card: ExerciseCard
    let today: LocalDay

    var body: some View {
        HStack(spacing: 6) {
            PartIcon(part: card.exercise.part)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.exercise.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        // グリッドは行の高さを一番高いカードに合わせるだけなので、背景を行の高さまで伸ばす
        .frame(minHeight: 48, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private var subtitle: String {
        guard let day = card.lastDay, let days = card.elapsedDays(today: today) else { return "未実施" }
        return "\(days)日前 " + String(format: "%02d/%02d", day.month, day.day)
    }
}
