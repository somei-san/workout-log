import Foundation
import GRDB
import Testing
@testable import WorkoutLog

struct AppDatabaseTests {
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.empty()
    }

    @Test func 種目を消すと記録とセットも消える() throws {
        try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: Date())
            try record.insert(db)
            var set = WorkoutSet(recordId: record.id!, position: 0, weight: 135, reps: 5)
            try set.insert(db)

            _ = try exercise.delete(db)

            #expect(try WorkoutRecord.fetchCount(db) == 0)
            #expect(try WorkoutSet.fetchCount(db) == 0)
        }
    }

    @Test func 記録を消すとセットも消え_同じ種目のほかの記録は残る() throws {
        try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            var kept = WorkoutRecord(exerciseId: exercise.id!, performedAt: Date())
            try kept.insert(db)
            var keptSet = WorkoutSet(recordId: kept.id!, position: 0, weight: 135, reps: 5)
            try keptSet.insert(db)
            var deleted = WorkoutRecord(exerciseId: exercise.id!, performedAt: Date())
            try deleted.insert(db)
            var deletedSet = WorkoutSet(recordId: deleted.id!, position: 0, weight: 140, reps: 3)
            try deletedSet.insert(db)

            _ = try deleted.delete(db)

            #expect(try WorkoutRecord.fetchAll(db).map(\.id) == [kept.id])
            #expect(try WorkoutSet.fetchAll(db).map(\.id) == [keptSet.id])
            #expect(try Exercise.fetchCount(db) == 1)
        }
    }

    @Test(arguments: [(-1, false), (0, true), (10, true), (11, false)])
    func 最初に並べるセット数は0から10だけ保存できる(count: Int, saves: Bool) throws {
        try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back, initialRowCount: count)
            if saves {
                try exercise.insert(db)
            } else {
                #expect(throws: DatabaseError.self) { try exercise.insert(db) }
            }
        }
    }

    @Test func 種目の1回の記録は新しい順で_同じ時刻なら後に作った記録が先() throws {
        let ids = try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            var ids: [Int64] = []
            for utc in ["2026-10-14T00:00:00Z", "2026-10-10T00:00:00Z", "2026-10-14T00:00:00Z"] {
                var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: try Date(utc, strategy: .iso8601))
                try record.insert(db)
                ids.append(record.id!)
            }
            return (ids, try RecordSummary.fetchAll(db, exerciseId: exercise.id!).map(\.record.id!))
        }
        #expect(ids.1 == [ids.0[2], ids.0[0], ids.0[1]])
    }

    @Test func 種目の無い記録と記録の無いセットは保存できない() throws {
        try database.writer.write { db in
            var record = WorkoutRecord(exerciseId: 999, performedAt: Date())
            #expect(throws: DatabaseError.self) { try record.insert(db) }
            var set = WorkoutSet(recordId: 999, position: 0, weight: 100, reps: 5)
            #expect(throws: DatabaseError.self) { try set.insert(db) }
        }
    }

    @Test func 記録は作った時点の時差を夏時間も含めて持つ() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        let summer = WorkoutRecord(exerciseId: 0, performedAt: try Date("2026-07-01T12:00:00Z", strategy: .iso8601), timeZone: newYork)
        let winter = WorkoutRecord(exerciseId: 0, performedAt: try Date("2026-12-01T12:00:00Z", strategy: .iso8601), timeZone: newYork)
        #expect(summer.utcOffset == -240)
        #expect(winter.utcOffset == -300)
    }

    @Test(arguments: [
        ("2026-10-16T22:30:00Z", "Asia/Tokyo", "2026-10-17"),
        ("2026-10-17T02:00:00Z", "America/New_York", "2026-10-16"),
    ])
    func 日付は記録した場所の時刻で切り出す(utc: String, timeZone: String, day: String) throws {
        let saved = try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            var record = WorkoutRecord(exerciseId: exercise.id!, performedAt: try Date(utc, strategy: .iso8601), timeZone: TimeZone(identifier: timeZone)!)
            try record.insert(db)
            return try WorkoutRecord.fetchOne(db, id: record.id!)!
        }
        let d = saved.day
        #expect(String(format: "%04d-%02d-%02d", d.year, d.month, d.day) == day)
    }

    @Test func 前回は同じ時刻なら先に作った記録() throws {
        try database.writer.write { db in
            var exercise = Exercise(name: "デッドリフト", part: .back)
            try exercise.insert(db)
            var other = Exercise(name: "ベンチプレス", part: .chest)
            try other.insert(db)
            func insert(_ exerciseId: Int64, _ utc: String) throws -> WorkoutRecord {
                var record = WorkoutRecord(exerciseId: exerciseId, performedAt: try Date(utc, strategy: .iso8601))
                try record.insert(db)
                return record
            }
            let a = try insert(exercise.id!, "2026-10-10T00:00:00Z")
            _ = try insert(other.id!, "2026-10-12T00:00:00Z")
            let b = try insert(exercise.id!, "2026-10-14T00:00:00Z")
            let c = try insert(exercise.id!, "2026-10-14T00:00:00Z")
            let draft = WorkoutRecord(exerciseId: exercise.id!, performedAt: c.performedAt)

            #expect(try a.previous(db)?.id == nil)
            #expect(try b.previous(db)?.id == a.id)
            #expect(try c.previous(db)?.id == b.id)
            #expect(try draft.previous(db)?.id == c.id)
        }
    }
}
