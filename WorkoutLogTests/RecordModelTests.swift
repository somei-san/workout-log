import Foundation
import GRDB
import Testing
@testable import WorkoutLog

@MainActor
struct RecordModelTests {
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.empty()
    }

    private func insertExercise(initialRowCount: Int = 0) throws -> Exercise {
        try database.writer.write { db in
            var exercise = Exercise(name: "ベンチプレス", part: .chest, initialRowCount: initialRowCount)
            try exercise.insert(db)
            return exercise
        }
    }

    private func insertRecord(_ exercise: Exercise, at date: Date, sets: [(Double, Int)]) throws -> WorkoutRecord {
        try database.writer.write { db in
            var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: date)
            try record.insert(db)
            for (i, (weight, reps)) in sets.enumerated() {
                var set = WorkoutSet(recordId: record.id!, position: i, weight: weight, reps: reps)
                try set.insert(db)
            }
            return record
        }
    }

    private func savedSets() throws -> [WorkoutSet] {
        try database.reader.read { db in try WorkoutSet.order(Column("position")).fetchAll(db) }
    }

    private func recordCount() throws -> Int {
        try database.reader.read { db in try WorkoutRecord.fetchCount(db) }
    }

    private func daysAgo(_ days: Int) -> Date {
        Clock.now().addingTimeInterval(-Double(days) * 24 * 60 * 60)
    }

    @Test func 新しい記録は空の行を種目の行の数だけ並べ_重さと回数がそろうまで記録を作らない() async throws {
        let exercise = try insertExercise(initialRowCount: 3)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        #expect(model.rows.count == 3)
        #expect(model.isEditing)

        let row = model.rows[0].id
        model.setValue(row, \.weight, "60")
        #expect(try recordCount() == 0)
        model.setValue(row, \.reps, "10")
        #expect(try recordCount() == 1)
        #expect(try savedSets().map { "\($0.weight)×\($0.reps)" } == ["60.0×10"])
    }

    @Test func 前日以前の記録は閲覧モードで開き_今日の記録は編集モードで開く() async throws {
        // 今の時刻で数えると、日付が変わる前後にテストを回したときに今日の記録が前日になる。今日を決めて渡す
        let now = try Date("2026-10-17T03:00:00Z", strategy: .iso8601)
        let day = LocalDay(now, timeZone: .current)
        let exercise = try insertExercise()
        let past = try insertRecord(exercise, at: now.addingTimeInterval(-2 * 24 * 60 * 60), sets: [(60, 10)])
        let today = try insertRecord(exercise, at: now, sets: [(60, 10)])

        let pastModel = RecordModel()
        try await pastModel.load(.existing(recordId: past.id!), database: database, today: day)
        #expect(pastModel.isPast)
        #expect(!pastModel.isEditing)

        let todayModel = RecordModel()
        try await todayModel.load(.existing(recordId: today.id!), database: database, today: day)
        #expect(!todayModel.isPast)
        #expect(todayModel.isEditing)
    }

    @Test func 前回はひとつ前の記録のセットをまとめて出し_前の記録が無ければなしと出す() async throws {
        let exercise = try insertExercise()
        let first = try insertRecord(exercise, at: daysAgo(3), sets: [(20, 8), (20, 8)])
        let second = try insertRecord(exercise, at: daysAgo(1), sets: [(22.5, 6)])

        let firstModel = RecordModel()
        try await firstModel.load(.existing(recordId: first.id!), database: database)
        #expect(firstModel.previousText == "なし")

        let secondModel = RecordModel()
        try await secondModel.load(.existing(recordId: second.id!), database: database)
        #expect(secondModel.previousText == "20kg×8×2")
    }

    @Test func 新しい記録の前回は_いちばん新しい記録のセット() async throws {
        let exercise = try insertExercise()
        _ = try insertRecord(exercise, at: daysAgo(3), sets: [(60, 10)])
        _ = try insertRecord(exercise, at: daysAgo(1), sets: [(20, 8), (20, 8)])

        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        #expect(model.previousText == "20kg×8×2")
    }

    @Test func 足した行は空で_セットは増えない() async throws {
        let exercise = try insertExercise()
        let record = try insertRecord(exercise, at: Clock.now(), sets: [(20, 8)])
        let model = RecordModel()
        try await model.load(.existing(recordId: record.id!), database: database)

        let row = model.addRow()
        #expect(model.rows.map(\.id) == [model.rows[0].id, row])
        #expect(model.value(row, \.weight) == "")
        #expect(model.value(row, \.reps) == "")
        #expect(try savedSets().count == 1)
    }

    @Test func 最後のセットは消さずに確認を求め_確認すると記録ごと消える() async throws {
        let exercise = try insertExercise()
        let record = try insertRecord(exercise, at: Clock.now(), sets: [(60, 10)])
        let model = RecordModel()
        try await model.load(.existing(recordId: record.id!), database: database)

        #expect(model.deleteRow(model.rows[0].id) == .needsConfirmation)
        #expect(try savedSets().count == 1)
        #expect(model.deleteRecord())
        #expect(try recordCount() == 0)
        #expect(try savedSets().isEmpty)
    }

    @Test func 行を消すと残りのセットの順番を詰め直す() async throws {
        let exercise = try insertExercise()
        let record = try insertRecord(exercise, at: Clock.now(), sets: [(60, 10), (62.5, 8), (65, 6)])
        let model = RecordModel()
        try await model.load(.existing(recordId: record.id!), database: database)

        #expect(model.deleteRow(model.rows[0].id) == .deleted)
        #expect(try savedSets().map { "\($0.position):\($0.weight)" } == ["0:62.5", "1:65.0"])
        #expect(model.rows.map(\.saved?.position) == [0, 1])
    }

    @Test func 保存したセットの回数を消したまま行を離れると保存した値に戻す() async throws {
        let exercise = try insertExercise()
        let record = try insertRecord(exercise, at: Clock.now(), sets: [(60, 10)])
        let model = RecordModel()
        try await model.load(.existing(recordId: record.id!), database: database)

        let row = model.rows[0].id
        model.setValue(row, \.reps, "")
        model.restoreIfCleared(row)
        #expect(model.value(row, \.reps) == "10")
        #expect(try savedSets().map(\.reps) == [10])
    }

    @Test func 最初のセットの前に変えた日付と時刻で記録を作る() async throws {
        let exercise = try insertExercise(initialRowCount: 1)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)

        let chosen = daysAgo(1)
        model.changeDate(chosen)
        #expect(try recordCount() == 0)
        let row = model.rows[0].id
        model.setValue(row, \.weight, "60")
        model.setValue(row, \.reps, "10")
        let performedAt = try await database.reader.read { db in try WorkoutRecord.fetchOne(db)?.performedAt }
        #expect(performedAt.map { abs($0.timeIntervalSince(chosen)) < 1 } == true)
    }

    @Test func 日付と時刻を変えなければ_開いた時刻で記録を作る() async throws {
        let exercise = try insertExercise(initialRowCount: 1)
        // 開いてから日付が変わっても、画面の上に出していた日付で残す
        let openedAt = daysAgo(1)
        let model = RecordModel(openedAt: openedAt)
        try await model.load(.new(exerciseId: exercise.id!), database: database)

        let row = model.rows[0].id
        model.setValue(row, \.weight, "60")
        model.setValue(row, \.reps, "10")
        let performedAt = try await database.reader.read { db in try WorkoutRecord.fetchOne(db)?.performedAt }
        #expect(performedAt.map { abs($0.timeIntervalSince(openedAt)) < 1 } == true)
    }

    @Test func 上の行の重さと回数を写せる_上の行が空なら写さない() async throws {
        let exercise = try insertExercise(initialRowCount: 2)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        let (first, second) = (model.rows[0].id, model.rows[1].id)

        #expect(!model.copyWeightAbove(second))
        #expect(!model.copyRepsAbove(second))
        model.setValue(first, \.weight, "60")
        model.setValue(first, \.reps, "10")
        #expect(model.copyWeightAbove(second))
        #expect(model.copyRepsAbove(second))
        #expect(model.value(second, \.weight) == "60")
        #expect(model.value(second, \.reps) == "10")
        #expect(try savedSets().count == 2)
    }

    @Test func 同じセットを足すと_いちばん下のセットの重さと回数だけを写して保存する() async throws {
        let exercise = try insertExercise()
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        #expect(model.lastSet == nil)
        #expect(!model.duplicateLastSet())

        let row = model.addRow()
        model.setValue(row, \.weight, "102.5")
        model.setValue(row, \.reps, "5")
        model.setValue(row, \.rpe, "8")
        #expect(model.duplicateLastSet())
        #expect(model.rows.count == 2)
        let sets = try savedSets()
        #expect(sets.map { "\($0.position):\($0.weight)×\($0.reps)" } == ["0:102.5×5", "1:102.5×5"])
        #expect(sets.map(\.rpe) == [8, nil])
    }

    @Test func 同じセットは_いちばん下のセットより後の空の行に入れる() async throws {
        let exercise = try insertExercise(initialRowCount: 3)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        model.setValue(model.rows[0].id, \.weight, "60")
        model.setValue(model.rows[0].id, \.reps, "10")

        #expect(model.duplicateLastSet())
        #expect(model.rows.count == 3)
        #expect(model.value(model.rows[1].id, \.weight) == "60")
        #expect(model.value(model.rows[2].id, \.weight) == "")
        #expect(try savedSets().map(\.position) == [0, 1])
    }

    @Test func セットになった時刻を入力時刻として保存し_値を直しても変えない() async throws {
        let exercise = try insertExercise(initialRowCount: 1)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        let row = model.rows[0].id
        model.setValue(row, \.weight, "60")
        model.setValue(row, \.reps, "10")
        let createdAt = try #require(try savedSets().first?.createdAt)
        #expect(abs(createdAt.timeIntervalSinceNow) < 5)

        try await Task.sleep(for: .milliseconds(50))
        model.setValue(row, \.reps, "9")
        #expect(try savedSets().first?.createdAt == createdAt)
    }

    @Test func 経過時間は_いちばん下のセットの入力時刻から_1時間未満の間だけ測る() async throws {
        let exercise = try insertExercise()
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        #expect(model.elapsedStart(now: Clock.now()) == nil)

        let row = model.addRow()
        model.setValue(row, \.weight, "60")
        model.setValue(row, \.reps, "10")
        let start = try #require(model.lastSet?.createdAt)
        #expect(model.elapsedStart(now: start.addingTimeInterval(59 * 60)) == start)
        #expect(model.elapsedStart(now: start.addingTimeInterval(60 * 60)) == nil)
    }

    @Test func 開いている間に日付が変わっても_経過時間は1時間未満なら測り続ける() async throws {
        let exercise = try insertExercise()
        // 23:55 に入れたセットを、日付が変わった 0:05 に見る。データベースの日時の丸めに合わせて秒で揃える
        let midnight = Calendar.current.startOfDay(for: Clock.now())
        let lastSetAt = midnight.addingTimeInterval(-5 * 60)
        let record = try insertRecord(exercise, at: lastSetAt, sets: [])
        try await database.writer.write { db in
            var set = WorkoutSet(recordId: record.id!, position: 0, weight: 60, reps: 10, createdAt: lastSetAt)
            try set.insert(db)
        }
        let model = RecordModel()
        try await model.load(.existing(recordId: record.id!), database: database,
                             today: LocalDay(lastSetAt, timeZone: .current))

        #expect(model.elapsedStart(now: midnight.addingTimeInterval(5 * 60)) == lastSetAt)
    }

    @Test func 経過時間は_種目でオフにしたときと_前日以前の記録と_入力時刻の無いセットでは測らない() async throws {
        var exercise = try insertExercise()
        // データベースに入れた日時はミリ秒までに丸まるので、読み直した値と比べられるよう秒で揃える
        let now = Date(timeIntervalSince1970: Clock.now().timeIntervalSince1970.rounded(.down))
        let set = { (record: WorkoutRecord) in
            try self.database.writer.write { db in
                var set = WorkoutSet(recordId: record.id!, position: 0, weight: 60, reps: 10, createdAt: now)
                try set.insert(db)
            }
        }

        let past = try insertRecord(exercise, at: daysAgo(2), sets: [])
        try set(past)
        let pastModel = RecordModel()
        try await pastModel.load(.existing(recordId: past.id!), database: database)
        #expect(pastModel.elapsedStart(now: now) == nil)

        // insertRecord のセットは入力時刻を持たない
        let old = try insertRecord(exercise, at: now, sets: [(60, 10)])
        let oldModel = RecordModel()
        try await oldModel.load(.existing(recordId: old.id!), database: database)
        #expect(oldModel.elapsedStart(now: now) == nil)

        let today = try insertRecord(exercise, at: now, sets: [])
        try set(today)
        let onModel = RecordModel()
        try await onModel.load(.existing(recordId: today.id!), database: database)
        #expect(onModel.elapsedStart(now: now) == now)

        exercise.showsElapsed = false
        let hidden = exercise
        try await database.writer.write { db in try hidden.update(db) }
        let offModel = RecordModel()
        try await offModel.load(.existing(recordId: today.id!), database: database)
        #expect(offModel.elapsedStart(now: now) == nil)
    }

    @Test func 空の欄の増減は上の行の値から_上の行も空なら0から() async throws {
        let exercise = try insertExercise(initialRowCount: 3)
        let model = RecordModel()
        try await model.load(.new(exerciseId: exercise.id!), database: database)
        let (first, second, third) = (model.rows[0].id, model.rows[1].id, model.rows[2].id)

        model.adjustWeight(first, by: 2.5)
        model.adjustReps(first, by: -1)
        #expect(model.value(first, \.weight) == "2.5")
        #expect(model.value(first, \.reps) == "1")

        model.setValue(second, \.weight, "60")
        model.setValue(second, \.reps, "10")
        model.adjustWeight(third, by: -2.5)
        model.adjustReps(third, by: 1)
        #expect(model.value(third, \.weight) == "57.5")
        #expect(model.value(third, \.reps) == "11")

        // 値の入った欄は、その値から増減する
        model.adjustWeight(third, by: 2.5)
        #expect(model.value(third, \.weight) == "60")
    }
}
