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
