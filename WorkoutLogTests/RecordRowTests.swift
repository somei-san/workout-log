import Foundation
import Testing
@testable import WorkoutLog

struct RecordRowTests {
    typealias SetRow = RecordView.SetRow

    private func saved(_ id: Int64, position: Int, weight: Double = 100, reps: Int = 5) -> SetRow {
        SetRow(saved: WorkoutSet(id: id, recordId: 1, position: position, weight: weight, reps: reps),
               weight: Format.weight(weight), reps: String(reps))
    }

    @Test func 重さは0以上_回数は1以上で_両方入るとセットになる() {
        #expect(SetRow(weight: "0", reps: "1").isFilled)
        #expect(!SetRow(weight: "100", reps: "0").isFilled)
        #expect(!SetRow(weight: "100", reps: "").isFilled)
        #expect(!SetRow(weight: "", reps: "5").isFilled)
        #expect(!SetRow(weight: ".", reps: "5").isFilled)
    }

    @Test func RPEは1から10の外を未入力として扱う() {
        #expect(SetRow(rpe: "1").rpeValue == 1)
        #expect(SetRow(rpe: "8.5").rpeValue == 8.5)
        #expect(SetRow(rpe: "10").rpeValue == 10)
        #expect(SetRow(rpe: "0.5").rpeValue == nil)
        #expect(SetRow(rpe: "10.5").rpeValue == nil)
        #expect(SetRow(rpe: "").rpeValue == nil)
    }

    @Test func RIRは0以上で_空なら未入力() {
        #expect(SetRow(rir: "0").rirValue == 0)
        #expect(SetRow(rir: "3").rirValue == 3)
        #expect(SetRow(rir: "").rirValue == nil)
        #expect(SetRow(rir: "-1").rirValue == nil)
    }

    @Test func 足す行には直前のセットの重さと回数を入れ_強度は引き継がない() {
        let rows = [SetRow(weight: "100", reps: "5", rpe: "8"), SetRow(weight: "102.5", reps: "3", rpe: "9", rir: "1"), SetRow()]
        let row = SetRow.next(after: rows, previous: [WorkoutSet(recordId: 0, position: 0, weight: 60, reps: 10)])
        #expect(row.weight == "102.5")
        #expect(row.reps == "3")
        #expect(row.rpe == "")
        #expect(row.rir == "")
    }

    @Test func セットがまだ無ければ前回の1セット目の値を入れる() {
        let previous = [WorkoutSet(recordId: 0, position: 0, weight: 60, reps: 10), WorkoutSet(recordId: 0, position: 1, weight: 70, reps: 8)]
        let row = SetRow.next(after: [SetRow()], previous: previous)
        #expect(row.weight == "60")
        #expect(row.reps == "10")
    }

    @Test func 前回も無ければ空の行を足す() {
        #expect(!SetRow.next(after: [], previous: []).isFilled)
        #expect(!SetRow.next(after: [], previous: nil).isFilled)
    }

    @Test func 保存したセットが1つだけの行を消すと記録ごと消える() {
        let rows = [saved(1, position: 0), SetRow()]
        #expect(SetRow.deletesRecord(rows, at: 0))
        #expect(!SetRow.deletesRecord(rows, at: 1))
        #expect(!SetRow.deletesRecord([saved(1, position: 0), saved(2, position: 1)], at: 0))
    }

    @Test func 行を消した後の残りのセットは画面の行の順に順番を詰め直す() {
        // 1 行目を消した後の残り
        let remaining = [SetRow(), saved(2, position: 2), saved(3, position: 3)]
        let sets = SetRow.renumbered(remaining)
        #expect(sets.map(\.id) == [2, 3])
        #expect(sets.map(\.position) == [1, 2])
    }

    @Test func 前日以前の記録は閲覧モードで_今日の記録は編集モードで開く() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let today = LocalDay(try Date("2026-10-17T03:00:00Z", strategy: .iso8601), timeZone: tokyo)
        // 東京の 2026-10-16 23:59 と 2026-10-17 00:00
        let yesterday = WorkoutRecord(exerciseId: 0, performedAt: try Date("2026-10-16T14:59:00Z", strategy: .iso8601), timeZone: tokyo)
        let todays = WorkoutRecord(exerciseId: 0, performedAt: try Date("2026-10-16T15:00:00Z", strategy: .iso8601), timeZone: tokyo)
        #expect(yesterday.isPast(today: today))
        #expect(!todays.isPast(today: today))
    }

    @Test func 同じ日に同じ種目の別の記録があるときだけ時刻を出す() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        func record(_ id: Int64, _ exerciseId: Int64, _ utc: String) throws -> WorkoutRecord {
            WorkoutRecord(id: id, exerciseId: exerciseId, performedAt: try Date(utc, strategy: .iso8601), timeZone: tokyo)
        }
        let morning = try record(1, 1, "2026-10-16T23:00:00Z") // 東京 10-17 08:00
        let evening = try record(2, 1, "2026-10-17T09:30:00Z") // 東京 10-17 18:30
        let other = try record(3, 2, "2026-10-17T10:00:00Z")
        let yesterday = try record(4, 1, "2026-10-16T10:00:00Z") // 東京 10-16 19:00
        let records = [morning, evening, other, yesterday]
        #expect(morning.sharesDay(with: records))
        #expect(evening.sharesDay(with: records))
        #expect(!other.sharesDay(with: records))
        #expect(!yesterday.sharesDay(with: records))
    }
}
