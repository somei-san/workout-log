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
}
