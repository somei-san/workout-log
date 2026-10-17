import GRDB
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("SQLite \(sqliteVersion)")
    }

    private var sqliteVersion: String {
        (try? DatabaseQueue().read { db in try String.fetchOne(db, sql: "SELECT sqlite_version()") }) ?? "?"
    }
}
