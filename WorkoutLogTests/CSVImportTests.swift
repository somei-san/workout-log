import Foundation
import GRDB
import Testing
@testable import WorkoutLog

struct CSVImportTests {
    let database: AppDatabase
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    init() throws {
        database = try AppDatabase.empty()
    }

    private func csv(_ rows: [String]) -> String {
        (["種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private func records(_ text: String) throws -> [CSVImport.ImportRecord] {
        try CSVImport.records(text).get()
    }

    private func problems(_ text: String) -> [String] {
        guard case .failure(let failure) = CSVImport.records(text) else { return [] }
        return failure.problems.map(\.text)
    }

    @Test func 書き出したCSVを空のデータベースに読み込むと同じCSVになる() throws {
        let source = try AppDatabase.empty()
        let exported = try source.writer.write { db in
            var bench = Exercise(name: "ベンチプレス", part: .chest)
            try bench.insert(db)
            var pullUp = Exercise(name: "懸垂", part: .back)
            try pullUp.insert(db)
            var first = WorkoutRecord(exerciseId: bench.id!, performedAt: try Date("2026-11-01T10:30:00Z", strategy: .iso8601), timeZone: tokyo, memo: "肩が重い, \"少し\"\n次は軽く")
            try first.insert(db)
            for (i, (weight, reps)) in [(60.0, 10), (62.5, 8)].enumerated() {
                var set = WorkoutSet(recordId: first.id!, position: i, weight: weight, reps: reps, rpe: 8)
                try set.insert(db)
            }
            var second = WorkoutRecord(exerciseId: pullUp.id!, performedAt: try Date("2026-11-02T22:15:00Z", strategy: .iso8601), timeZone: tokyo)
            try second.insert(db)
            var set = WorkoutSet(recordId: second.id!, position: 0, weight: 0, reps: 8, rir: 2)
            try set.insert(db)
            return try CSVExport.make(db)
        }

        let imported = try database.writer.write { db in
            try CSVImport.save(db, try records(exported), timeZone: tokyo)
            return try CSVExport.make(db)
        }

        #expect(imported == exported)
    }

    @Test func 同じCSVを2回読み込んでも記録は重ならない() throws {
        let text = csv([
            "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
            "ベンチプレス,胸,2026/11/01,19:30,2,60,8,,,",
            "懸垂,背中,2026/11/03,7:15,1,0,8,,,",
        ])
        let (first, second, count) = try database.writer.write { db in
            let first = try CSVImport.save(db, try records(text), timeZone: tokyo)
            let second = try CSVImport.save(db, try records(text), timeZone: tokyo)
            return (first, second, try WorkoutRecord.fetchCount(db))
        }
        #expect(first.records.count == 2)
        #expect(first.setCount == 3)
        #expect(second.records.isEmpty)
        #expect(second.skipped == 2)
        #expect(count == 2)
    }

    @Test func 今ある記録と同じ分の記録は_秒が違っても読み込まない() throws {
        let plan = try database.writer.write { db in
            var bench = Exercise(name: "ベンチプレス", part: .chest)
            try bench.insert(db)
            var record = WorkoutRecord(exerciseId: bench.id!, performedAt: try Date("2026-11-01T10:30:42Z", strategy: .iso8601), timeZone: tokyo)
            try record.insert(db)
            return try CSVImport.plan(db, try records(csv([
                "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
                "ベンチプレス,胸,2026/11/01,19:31,1,60,10,,,",
            ])), timeZone: tokyo)
        }
        #expect(plan.skipped == 1)
        #expect(plan.records.map(\.at.minute) == [31])
    }

    @Test func 名前と部位が同じ種目に足し_無ければ種目を作る() throws {
        let (plan, exercises) = try database.writer.write { db in
            var bench = Exercise(name: "ベンチプレス", part: .chest)
            try bench.insert(db)
            let plan = try CSVImport.save(db, try records(csv([
                "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
                "ベンチプレス,肩,2026/11/01,19:30,1,40,10,,,",
                "ディップス,胸,2026/11/01,20:00,1,0,10,,,",
                "ディップス,胸,2026/11/02,20:00,1,0,10,,,",
            ])), timeZone: tokyo)
            return (plan, try Exercise.order(Column("id")).fetchAll(db))
        }
        #expect(plan.newExercises == ["ベンチプレス(肩)", "ディップス(胸)"])
        #expect(exercises.map(\.name) == ["ベンチプレス", "ベンチプレス", "ディップス"])
        #expect(exercises.map(\.part) == [.chest, .shoulder, .chest])
    }

    @Test func 同じ記録の行はセットの順に並べ_メモは1行だけに書いてもよい() throws {
        let result = try records(csv([
            "ベンチプレス,胸,2026/11/01,19:30,2,62.5,8,8.5,,",
            "懸垂,背中,2026/11/01,19:30,1,0,8,,2,",
            "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,肩が重い",
        ]))
        #expect(result.map(\.exercise) == ["ベンチプレス", "懸垂"])
        #expect(result[0].sets.map(\.weight) == [60, 62.5])
        #expect(result[0].sets.map(\.rpe) == [nil, 8.5])
        #expect(result[0].memo == "肩が重い")
        #expect(result[1].sets.map(\.rir) == [2])
    }

    @Test func 読めない行をすべて行番号つきで返す() {
        let result = problems(csv([
            "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
            ",肩甲,2026-11-01,7時,0,-5,10.5,高い,1.5,",
            "ベンチプレス,胸,2026/02/30,24:00,1,60,0,0.5,,",
            "ベンチプレス,胸,2026/11/01,19:30",
            "ベンチプレス,胸,2026/11/01,19:30,2,60,10,11,,",
        ]))
        #expect(result == [
            "3 行目: 種目が空です",
            "3 行目: 部位「肩甲」は読めません。胸・肩・背中・腕・腹・足・その他のどれかにします",
            "3 行目: 日付「2026-11-01」は読めません。2026/11/07 の形にします",
            "3 行目: 時刻「7時」は読めません。19:30 の形にします",
            "3 行目: セット「0」は読めません。1 以上の整数にします",
            "3 行目: 重さ「-5」は読めません。0 以上の数にします",
            "3 行目: 回数「10.5」は読めません。1 以上の整数にします",
            "3 行目: RPE「高い」は読めません。空か、1〜10 の数にします",
            "3 行目: RIR「1.5」は読めません。空か、0 以上の整数にします",
            "4 行目: 日付「2026/02/30」はありません",
            "4 行目: 時刻「24:00」はありません",
            "4 行目: 回数「0」は読めません。1 以上の整数にします",
            "4 行目: RPE「0.5」は読めません。空か、1〜10 の数にします",
            "5 行目: 列が 10 個ではなく 4 個です",
            "6 行目: RPE「11」は読めません。空か、1〜10 の数にします",
        ])
    }

    @Test func どの値も空の行は飛ばす() throws {
        let result = try records(csv([
            "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
            ",,,,,,,,,",
            "",
        ]))
        #expect(result.count == 1)
    }

    @Test func 名前と部位が同じ種目が2つあれば_先に作った種目に足し_どちらの記録とも比べる() throws {
        let (plan, first, second) = try database.writer.write { db in
            var first = Exercise(name: "ベンチプレス", part: .chest)
            try first.insert(db)
            var second = Exercise(name: "ベンチプレス", part: .chest)
            try second.insert(db)
            var record = WorkoutRecord(exerciseId: second.id!, performedAt: try Date("2026-11-01T10:30:00Z", strategy: .iso8601), timeZone: tokyo)
            try record.insert(db)
            let plan = try CSVImport.save(db, try records(csv([
                "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,",
                "ベンチプレス,胸,2026/11/02,19:30,1,60,10,,,",
            ])), timeZone: tokyo)
            let count = { (id: Int64) in try WorkoutRecord.filter(Column("exerciseId") == id).fetchCount(db) }
            return (plan, try count(first.id!), try count(second.id!))
        }
        #expect(plan.skipped == 1)
        #expect(plan.newExercises.isEmpty)
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test func 非表示の種目に足すときは_その種目を知らせる() throws {
        let plan = try database.writer.write { db in
            var hidden = Exercise(name: "ディップス", part: .chest, isHidden: true)
            try hidden.insert(db)
            return try CSVImport.plan(db, try records(csv([
                "ディップス,胸,2026/11/01,19:30,1,0,10,,,",
                "ディップス,胸,2026/11/02,19:30,1,0,10,,,",
            ])), timeZone: tokyo)
        }
        #expect(plan.hiddenExercises == ["ディップス(胸)"])
        #expect(plan.newExercises.isEmpty)
    }

    @Test func 夏時間に切り替わって無い時刻の記録も_2回読み込んで重ならない() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        let text = csv(["ベンチプレス,胸,2026/03/08,02:30,1,60,10,,,"])
        let (second, count) = try database.writer.write { db in
            try CSVImport.save(db, try records(text), timeZone: newYork)
            let second = try CSVImport.save(db, try records(text), timeZone: newYork)
            return (second, try WorkoutRecord.fetchCount(db))
        }
        #expect(second.skipped == 1)
        #expect(count == 1)
    }

    @Test func 同じ記録でセットやメモが食い違う行は読めない() {
        let result = problems(csv([
            "ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,肩が重い",
            "ベンチプレス,胸,2026/11/01,19:30,1,60,8,,,肩が軽い",
        ]))
        #expect(result == [
            "3 行目: 2 行目と同じ記録で、セットが同じ 1 です",
            "3 行目: 2 行目と同じ記録で、メモが違います。同じメモにするか、1 行だけに書きます",
        ])
    }

    @Test func 見出しが違うか記録の行が無いと読めない() {
        #expect(problems("種目,部位,日付\r\n") == ["1 行目: 列の見出しを「種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ」にします"])
        #expect(problems("種目,部位\r\na,\"b") == [
            "1 行目: 列の見出しを「種目,部位,日付,時刻,セット,重さ(kg),回数,RPE,RIR,メモ」にします",
            "2 行目: ダブルクォート「\"」が閉じていません",
        ])
        #expect(problems(csv([])) == ["記録の行がありません"])
        #expect(problems("") == ["ファイルが空です"])
    }

    @Test func ダブルクォートの中のカンマと改行を読み_行番号は改行も数える() {
        let parsed = CSVImport.fields("a,\"b,\"\"c\"\"\r\nd\"\r\n\r\ne,f")
        #expect(parsed.problems.isEmpty)
        #expect(parsed.lines.map(\.line) == [1, 4])
        #expect(parsed.lines.map(\.fields) == [["a", "b,\"c\"\r\nd"], ["e", "f"]])
        #expect(CSVImport.fields("a,\"b").problems.map(\.text) == ["1 行目: ダブルクォート「\"」が閉じていません"])
    }

    @Test func BOMつきのUTF8とShiftJISのCSVを読む() throws {
        let text = csv(["ベンチプレス,胸,2026/11/01,19:30,1,60,10,,,"])
        let utf8 = Data("\u{FEFF}".utf8) + Data(text.utf8)
        let shiftJIS = try #require(text.data(using: .shiftJIS))
        for data in [utf8, shiftJIS] {
            let result = try CSVImport.records(data).get()
            #expect(result.map(\.exercise) == ["ベンチプレス"])
        }
    }

    @Test func 見本のCSVは読み込める() throws {
        let result = try records(CSVImport.sample)
        #expect(result.count == 2)
    }

    @Test func 時刻は読み込むタイムゾーンの時刻として_その日付の時差で保存する() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        let saved = try database.writer.write { db in
            try CSVImport.save(db, try records(csv([
                "ベンチプレス,胸,2026/07/01,08:00,1,60,10,,,",
                "ベンチプレス,胸,2026/12/01,08:00,1,60,10,,,",
            ])), timeZone: newYork)
            return try WorkoutRecord.order(Column("performedAt")).fetchAll(db)
        }
        #expect(saved.map(\.utcOffset) == [-240, -300])
        #expect(saved.map(\.performedAt) == [
            try Date("2026-07-01T12:00:00Z", strategy: .iso8601),
            try Date("2026-12-01T13:00:00Z", strategy: .iso8601),
        ])
    }
}
