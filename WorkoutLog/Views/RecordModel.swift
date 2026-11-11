import Foundation
import GRDB
import Observation

/// 種目の記録の画面の状態と、行の保存と削除。画面に頼らずに単体テストで確かめられるよう、RecordView から分けている。
/// 打っている欄（FocusState）と画面を閉じることは画面の側で持ち、ここでは行の ID で受け取る
@MainActor @Observable
final class RecordModel {
    typealias SetRow = RecordView.SetRow

    enum LoadError: Error {
        case notFound
    }

    enum DeleteOutcome: Equatable {
        case deleted
        /// 最後のセットなので、消すと記録ごと消える。消さずに確認を出す
        case needsConfirmation
    }

    private(set) var exercise: Exercise?
    /// 保存した 1 回の記録。新しい記録では、最初のセットができるまで nil
    private(set) var record: WorkoutRecord?
    /// 新しい記録で、最初のセットの前に選んだ日付と時刻
    private(set) var chosenAt: Date?
    private let openedAt: Date
    var rows: [SetRow] = []
    var memo = ""
    private(set) var previousSets: [WorkoutSet]?
    private(set) var sharesDay = false
    private(set) var isLoaded = false
    var isEditing = true
    /// 前日以前の記録。閲覧モードで開く
    private(set) var isPast = false

    @ObservationIgnored private var database: AppDatabase?

    init(openedAt: Date = Clock.now()) {
        self.openedAt = openedAt
    }

    var performedAt: Date {
        record?.performedAt ?? chosenAt ?? openedAt
    }

    var previousText: String {
        guard let previousSets else { return "" }
        return previousSets.isEmpty ? "なし" : Format.sets(previousSets)
    }

    // MARK: - 読み込み

    private struct Loaded: Sendable {
        var exercise: Exercise
        var record: WorkoutRecord?
        var sets: [WorkoutSet]
    }

    /// 記録を読み込む。2 回目からは何もしない。記録か種目が無ければ LoadError.notFound を投げる
    func load(_ target: RecordView.Target, database: AppDatabase, today: LocalDay = .today()) async throws {
        guard !isLoaded else { return }
        isLoaded = true
        self.database = database
        let loaded = try await database.reader.read { db -> Loaded in
            switch target {
            case .existing(let recordId):
                guard let record = try WorkoutRecord.fetchOne(db, id: recordId),
                      let exercise = try Exercise.fetchOne(db, id: record.exerciseId)
                else { throw LoadError.notFound }
                return Loaded(exercise: exercise, record: record, sets: try record.fetchSets(db))
            case .new(let exerciseId):
                guard let exercise = try Exercise.fetchOne(db, id: exerciseId) else { throw LoadError.notFound }
                return Loaded(exercise: exercise, record: nil, sets: [])
            }
        }
        exercise = loaded.exercise
        record = loaded.record
        memo = loaded.record?.memo ?? ""
        isPast = loaded.record?.isPast(today: today) ?? false
        isEditing = !isPast
        rows = loaded.record == nil
            ? (0..<loaded.exercise.initialRowCount).map { _ in SetRow() }
            : loaded.sets.map { set in
                SetRow(saved: set, weight: Format.weight(set.weight), reps: String(set.reps),
                       rpe: set.rpe.map(Format.weight) ?? "", rir: set.rir.map(String.init) ?? "")
            }
        await loadContext()
    }

    /// 前回と、同じ日に別の記録があるか。日付と時刻を変えると変わるので、変えるたびに読み直す
    func loadContext() async {
        guard let database, let exerciseId = exercise?.id else { return }
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

    // MARK: - 編集

    /// 空の行を足し、その行の ID を返す
    @discardableResult
    func addRow() -> UUID {
        let row = SetRow()
        rows.append(row)
        return row.id
    }

    func index(of rowId: UUID) -> Int? {
        rows.firstIndex { $0.id == rowId }
    }

    /// 行の 1 つ上の行。同じ重さや回数でセットを続けるときに写す元
    func rowAbove(_ rowId: UUID) -> SetRow? {
        guard let i = index(of: rowId), i > 0 else { return nil }
        return rows[i - 1]
    }

    func value(_ rowId: UUID, _ keyPath: WritableKeyPath<SetRow, String>) -> String {
        index(of: rowId).map { rows[$0][keyPath: keyPath] } ?? ""
    }

    /// 欄の値を変えて保存する
    func setValue(_ rowId: UUID, _ keyPath: WritableKeyPath<SetRow, String>, _ value: String) {
        guard let i = index(of: rowId), rows[i][keyPath: keyPath] != value else { return }
        rows[i][keyPath: keyPath] = value
        persist(i)
    }

    /// 欄の値から入れられない文字を取り除いて保存する。
    /// 打った値が入った後に、画面の onChange から呼ぶ。Binding の set の中で取り除くと、
    /// 「1a00」と打った欄の表示が「1a00」のまま描き直されなかったため。
    func removeDisallowed(_ rowId: UUID, _ keyPath: WritableKeyPath<SetRow, String>, filter: (String) -> String) {
        guard let i = index(of: rowId) else { return }
        let filtered = filter(rows[i][keyPath: keyPath])
        guard filtered != rows[i][keyPath: keyPath] else { return }
        rows[i][keyPath: keyPath] = filtered
        persist(i)
    }

    func adjustWeight(_ rowId: UUID, by delta: Double) {
        guard let i = index(of: rowId) else { return }
        rows[i].weight = Format.weight(max(0, (rows[i].weightValue ?? 0) + delta))
        persist(i)
    }

    func adjustReps(_ rowId: UUID, by delta: Int) {
        guard let i = index(of: rowId) else { return }
        rows[i].reps = String(max(1, (rows[i].repsValue ?? 0) + delta))
        persist(i)
    }

    /// 1 つ上の行の重さを写す。写す値が無ければ false を返す
    func copyWeightAbove(_ rowId: UUID) -> Bool {
        guard let i = index(of: rowId), let above = rowAbove(rowId)?.weightValue else { return false }
        rows[i].weight = Format.weight(above)
        persist(i)
        return true
    }

    /// 1 つ上の行の回数を写す。写す値が無ければ false を返す
    func copyRepsAbove(_ rowId: UUID) -> Bool {
        guard let i = index(of: rowId), let above = rowAbove(rowId)?.repsValue else { return false }
        rows[i].reps = String(above)
        persist(i)
        return true
    }

    /// 行を保存する。重さと回数がそろっていない行は保存しない。
    /// 新しい記録では、最初のセットを保存するときに、画面の上に出している日付と時刻で 1 回の記録も作る。
    /// 保存した時刻で作ると、開いてから日付が変わったときに、出していた日付と違う日の記録になるため
    private func persist(_ i: Int) {
        let row = rows[i]
        guard let database, let weight = row.weightValue, let reps = row.repsValue, let exerciseId = exercise?.id else { return }
        let record = record, memo = memo, performedAt = performedAt
        let rpe = row.rpeValue, rir = row.rirValue
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
    func restoreIfCleared(_ rowId: UUID) {
        // 空の行は保存しないので、消した値はデータベースに届かず、戻さないと表示とずれる
        guard let i = index(of: rowId), let saved = rows[i].saved, !rows[i].isFilled else { return }
        rows[i].weight = Format.weight(saved.weight)
        rows[i].reps = String(saved.reps)
    }

    func saveMemo() {
        guard let database, var record, record.memo != memo else { return }
        record.memo = memo
        do {
            try database.writer.write { db in try record.update(db) }
            self.record = record
        } catch {
            print("メモを保存できない: \(error)")
        }
    }

    /// 行を消す。最後のセットのときは記録ごと消えるので、消さずに needsConfirmation を返す
    func deleteRow(_ rowId: UUID) -> DeleteOutcome? {
        guard let database, let i = index(of: rowId) else { return nil }
        if SetRow.deletesRecord(rows, at: i) {
            return .needsConfirmation
        }
        var remaining = rows
        remaining.remove(at: i)
        let deleted = rows[i].saved
        let renumbered = SetRow.renumbered(remaining)
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
            return .deleted
        } catch {
            print("セットを消せない: \(error)")
            return nil
        }
    }

    /// 1 回の記録を消す。消せたら true を返す
    func deleteRecord() -> Bool {
        guard let database, let record else { return false }
        do {
            _ = try database.writer.write { db in try record.delete(db) }
            return true
        } catch {
            print("記録を消せない: \(error)")
            return false
        }
    }

    /// 日付と時刻を変える。新しい記録で最初のセットの前なら、選んだ値を覚えておき、最初のセットを保存するときに使う。
    /// 前回と同じ日の記録が変わるので、変えた後に loadContext で読み直す
    func changeDate(_ date: Date) {
        if let record = record?.moved(to: date) {
            guard let database else { return }
            do {
                try database.writer.write { db in try record.update(db) }
                self.record = record
            } catch {
                print("日付と時刻を変えられない: \(error)")
            }
        } else {
            chosenAt = date
        }
    }
}
