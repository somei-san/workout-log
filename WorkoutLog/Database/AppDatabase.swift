import Foundation
import GRDB

/// アプリのデータベース。開くときにマイグレーションを済ませる
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    // 実機に入るのは DEBUG ビルドで、実際の記録が入っている。記録を消さないため、
    // eraseDatabaseOnSchemaChange は使わない。実機で動かしたマイグレーションは書き換えず、新しく足す
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "exercise") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("part", .text).notNull()
                t.column("isHidden", .boolean).notNull().defaults(to: false)
                t.column("initialRowCount", .integer).notNull().defaults(to: 0)
                    .check { $0 >= 0 && $0 <= 10 }
            }
            try db.create(table: "record") { t in
                t.autoIncrementedPrimaryKey("id")
                // index は下の (exerciseId, performedAt) で兼ねる
                t.belongsTo("exercise", onDelete: .cascade, indexed: false).notNull()
                t.column("performedAt", .datetime).notNull()
                t.column("utcOffset", .integer).notNull()
                t.column("memo", .text).notNull().defaults(to: "")
            }
            try db.create(index: "record_on_exerciseId_performedAt", on: "record", columns: ["exerciseId", "performedAt"])
            try db.create(table: "workoutSet") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("record", onDelete: .cascade).notNull()
                t.column("position", .integer).notNull()
                t.column("weight", .double).notNull()
                t.column("reps", .integer).notNull()
                t.column("rpe", .double)
                t.column("rir", .integer)
            }
        }
        return migrator
    }
}

extension AppDatabase {
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return try AppDatabase(DatabasePool(path: dir.appendingPathComponent("db.sqlite").path))
        } catch {
            fatalError("データベースを開けない: \(error)")
        }
    }

    /// メモリ上の空のデータベース
    static func empty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }
}
