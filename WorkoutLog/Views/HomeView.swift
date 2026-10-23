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
                let visible = sorted(cards.filter { !$0.exercise.isHidden })
                switch mode {
                case .all:
                    grid(visible)
                case .part:
                    ForEach(partOrder(visible), id: \.self) { part in
                        let group = visible.filter { $0.exercise.part == part }
                        if !group.isEmpty {
                            Text(part.label)
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            grid(group)
                        }
                    }
                }
                let hidden = sorted(cards.filter(\.exercise.isHidden))
                if !hidden.isEmpty {
                    DisclosureGroup("非表示の種目(\(hidden.count))", isExpanded: $showsHidden) {
                        grid(hidden)
                    }
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("種目がありません", systemImage: "dumbbell", description: Text("右上の「＋」で種目を追加します"))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("見方", selection: $mode) {
                        Text("すべて").tag(Mode.all)
                        Text("部位").tag(Mode.part)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
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

    /// 今の見方の並べ方で並べる。未実施の種目は、経過日数がいちばん大きく、頻度が 0 として扱う。
    /// 値が同じなら経過日数の大きい順、それも同じなら名前の順
    private func sorted(_ cards: [ExerciseCard]) -> [ExerciseCard] {
        let rule = rule
        return cards.sorted { a, b in
            let ea = a.elapsedDays(today: today) ?? .max, eb = b.elapsedDays(today: today) ?? .max
            if !rule.isElapsed, a.frequency(rule) != b.frequency(rule) {
                return rule.isDescending ? a.frequency(rule) > b.frequency(rule) : a.frequency(rule) < b.frequency(rule)
            }
            if rule.isElapsed, !rule.isDescending, ea != eb {
                return ea < eb
            }
            return ea != eb ? ea > eb : a.exercise.name < b.exercise.name
        }
    }

    /// 部位の見方の区切りの順。経過日数なら胸、肩、…、その他の順。
    /// 頻度なら、その部位の表示中の種目の頻度の合計で、選んだ向きに並べる。合計が同じなら胸、肩、…の順
    private func partOrder(_ visible: [ExerciseCard]) -> [Part] {
        let rule = rule
        guard !rule.isElapsed else { return Part.allCases }
        let total = Dictionary(grouping: visible, by: \.exercise.part).mapValues { $0.reduce(0) { $0 + $1.frequency(rule) } }
        return Part.allCases.enumerated().sorted { a, b in
            let ta = total[a.element] ?? 0, tb = total[b.element] ?? 0
            if ta != tb { return rule.isDescending ? ta > tb : ta < tb }
            return a.offset < b.offset
        }.map(\.element)
    }
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
