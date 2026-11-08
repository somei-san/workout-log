import Foundation
import GRDB

/// 書き出す CSV と同じ列の CSV から、記録を読み込む
enum CSVImport {
    /// 記録した場所の日付と時刻。分まで
    struct LocalTime: Hashable, Sendable {
        var year, month, day, hour, minute: Int

        private static let gmt: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }()

        init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
            (self.year, self.month, self.day, self.hour, self.minute) = (year, month, day, hour, minute)
        }

        /// 保存した記録の、記録した場所の日付と時刻
        init(_ record: WorkoutRecord) {
            self.init(record.performedAt, utcOffset: record.utcOffset)
        }

        init(_ date: Date, utcOffset: Int) {
            let c = Self.gmt.dateComponents([.year, .month, .day, .hour, .minute], from: date.addingTimeInterval(TimeInterval(utcOffset * 60)))
            self.init(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
        }

        /// timeZone の時刻として読んだ日時。夏時間に切り替わって無い時刻は、Calendar が後ろにずらす
        func date(in timeZone: TimeZone) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        /// timeZone で保存したときの日付と時刻。夏時間に切り替わって無い時刻は、保存する時刻に変わる
        func saved(in timeZone: TimeZone) -> LocalTime {
            let date = date(in: timeZone)
            return LocalTime(date, utcOffset: timeZone.secondsFromGMT(for: date) / 60)
        }
    }

    /// CSV の同じ「種目・部位・日付・時刻」の行をまとめた、1 回の記録
    struct ImportRecord: Sendable {
        var exercise: String
        var part: Part
        var at: LocalTime
        var memo: String
        /// セットの列の順に並べたセット。recordId と position は保存するときに決める
        var sets: [WorkoutSet]
    }

    /// 読めない行と、その理由
    struct Problem: Hashable, Sendable {
        /// ファイル全体の問題のときは nil
        var line: Int?
        var message: String

        var text: String { line.map { "\($0) 行目: \(message)" } ?? message }
    }

    struct Failure: Error {
        var problems: [Problem]
    }

    /// 読み込む前に見せる内容
    struct Plan: Sendable {
        /// 足す記録。今ある記録と重なるものは除く
        var records: [ImportRecord]
        /// 今ある記録と重なっていて、読み込まない記録の数
        var skipped: Int
        /// 新しく作る種目の「名前(部位)」
        var newExercises: [String]
        /// 記録を足す、非表示の種目の「名前(部位)」。足してもホームに出ないことを伝えるため
        var hiddenExercises: [String]

        var setCount: Int { records.reduce(0) { $0 + $1.sets.count } }
    }

    // MARK: - 読む

    /// ファイルの中身を読み、1 回の記録にまとめる。1 行でも読めなければ、読めない行をすべて返す
    static func records(_ data: Data) -> Result<[ImportRecord], Failure> {
        guard let text = decode(data) else {
            return .failure(Failure(problems: [Problem(message: "文字コードが UTF-8 でも Shift_JIS でもありません。UTF-8 で保存し直します")]))
        }
        return records(text)
    }

    static func records(_ text: String) -> Result<[ImportRecord], Failure> {
        let parsed = fields(text)
        var problems = parsed.problems
        guard let first = parsed.lines.first else {
            return .failure(Failure(problems: problems + [Problem(message: "ファイルが空です")]))
        }
        guard first.fields == CSVExport.header else {
            let header = CSVExport.header.joined(separator: ",")
            return .failure(Failure(problems: [Problem(line: first.line, message: "列の見出しを「\(header)」にします")] + problems))
        }
        var rows: [(line: Int, record: ImportRecord, setNumber: Int)] = []
        for line in parsed.lines.dropFirst() {
            switch row(line.fields) {
            case .success(let (record, setNumber)): rows.append((line.line, record, setNumber))
            case .failure(let failure): problems += failure.problems.map { Problem(line: line.line, message: $0.message) }
            }
        }
        if problems.isEmpty, rows.isEmpty {
            problems.append(Problem(message: "記録の行がありません"))
        }

        // 同じ「種目・部位・日付・時刻」の行を、出てきた順に 1 回の記録にまとめる
        struct Key: Hashable { var exercise: String; var part: Part; var at: LocalTime }
        var order: [Key] = []
        var groups: [Key: [(line: Int, record: ImportRecord, setNumber: Int)]] = [:]
        for row in rows {
            let key = Key(exercise: row.record.exercise, part: row.record.part, at: row.record.at)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        var records: [ImportRecord] = []
        for key in order {
            let group = groups[key]!
            var seen: [Int: Int] = [:]
            for row in group {
                if let line = seen[row.setNumber] {
                    problems.append(Problem(line: row.line, message: "\(line) 行目と同じ記録で、セットが同じ \(row.setNumber) です"))
                }
                seen[row.setNumber] = seen[row.setNumber] ?? row.line
            }
            // メモは 1 行だけに書いてもよい。空でない行どうしでメモが違うときは、どれを使うか決められない
            let memos = group.filter { !$0.record.memo.isEmpty }
            if let first = memos.first, let other = memos.first(where: { $0.record.memo != first.record.memo }) {
                problems.append(Problem(line: other.line, message: "\(first.line) 行目と同じ記録で、メモが違います。同じメモにするか、1 行だけに書きます"))
            }
            var record = group[0].record
            record.memo = memos.first?.record.memo ?? ""
            record.sets = group.sorted { $0.setNumber < $1.setNumber }.flatMap(\.record.sets)
            records.append(record)
        }
        return problems.isEmpty ? .success(records) : .failure(Failure(problems: problems))
    }

    /// 1 行を読む。セットを 1 つ持つ記録と、セットの列の値を返す。
    /// 値の範囲は、記録の画面がセットとして扱う範囲(RecordView.SetRow)に合わせる
    private static func row(_ fields: [String]) -> Result<(ImportRecord, Int), Failure> {
        guard fields.count == CSVExport.header.count else {
            return .failure(Failure(problems: [Problem(message: "列が \(CSVExport.header.count) 個ではなく \(fields.count) 個です")]))
        }
        // メモ以外は、前後の空白を取り除いて読む
        let value = fields.map { $0.trimmingCharacters(in: .whitespaces) }
        var problems: [String] = []

        let name = value[0]
        if name.isEmpty { problems.append("種目が空です") }
        let part = Part.allCases.first { $0.label == value[1] }
        if part == nil {
            problems.append("部位「\(value[1])」は読めません。\(Part.allCases.map(\.label).joined(separator: "・"))のどれかにします")
        }
        let date = numbers(value[2], separator: "/", digits: [4...4, 1...2, 1...2])
        let time = numbers(value[3], separator: ":", digits: [1...2, 2...2])
        var at: LocalTime?
        if let date, let time {
            let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: date[0], month: date[1], day: date[2])
            if !components.isValidDate { problems.append("日付「\(value[2])」はありません") }
            if time[0] > 23 || time[1] > 59 { problems.append("時刻「\(value[3])」はありません") }
            at = LocalTime(year: date[0], month: date[1], day: date[2], hour: time[0], minute: time[1])
        }
        if date == nil { problems.append("日付「\(value[2])」は読めません。2026/11/07 の形にします") }
        if time == nil { problems.append("時刻「\(value[3])」は読めません。19:30 の形にします") }
        let setNumber = integer(value[4]).flatMap { $0 >= 1 ? $0 : nil }
        if setNumber == nil { problems.append("セット「\(value[4])」は読めません。1 以上の整数にします") }
        let weight = decimal(value[5])
        if weight == nil { problems.append("重さ「\(value[5])」は読めません。0 以上の数にします") }
        let reps = integer(value[6]).flatMap { $0 >= 1 ? $0 : nil }
        if reps == nil { problems.append("回数「\(value[6])」は読めません。1 以上の整数にします") }
        let rpe = value[7].isEmpty ? nil : decimal(value[7]).flatMap { (1...10).contains($0) ? $0 : nil }
        if !value[7].isEmpty, rpe == nil { problems.append("RPE「\(value[7])」は読めません。空か、1〜10 の数にします") }
        let rir = value[8].isEmpty ? nil : integer(value[8])
        if !value[8].isEmpty, rir == nil { problems.append("RIR「\(value[8])」は読めません。空か、0 以上の整数にします") }

        guard problems.isEmpty, let part, let at, let setNumber, let weight, let reps else {
            return .failure(Failure(problems: problems.map { Problem(message: $0) }))
        }
        let set = WorkoutSet(recordId: 0, position: 0, weight: weight, reps: reps, rpe: rpe, rir: rir)
        return .success((ImportRecord(exercise: name, part: part, at: at, memo: fields[9], sets: [set]), setNumber))
    }

    /// 「2026/11/7」のように区切った数字。区切りごとの桁数が digits に入らなければ nil
    private static func numbers(_ text: String, separator: Character, digits: [ClosedRange<Int>]) -> [Int]? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == digits.count else { return nil }
        var numbers: [Int] = []
        for (part, range) in zip(parts, digits) {
            guard range.contains(part.count), let number = integer(String(part)) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// 0 以上の整数。半角の数字だけ
    private static func integer(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// 0 以上の数。半角の数字と「.」1 つだけ
    private static func decimal(_ text: String) -> Double? {
        guard text.contains(where: \.isNumber),
              text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              text.filter({ $0 == "." }).count <= 1
        else { return nil }
        return Double(text)
    }

    /// UTF-8 で読み、読めなければ Shift_JIS で読む。日本語の Excel は、CSV を Shift_JIS で保存するため
    static func decode(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return nil }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// CSV を行と値に分ける。ダブルクォートで囲んだ値は、カンマと改行を含められ、「""」で「"」を表す。
    /// line は、その行が始まるファイルの行番号。値の中の改行も 1 行と数える。
    /// どの値も空の行は飛ばす。Excel は、表の下にカンマだけの行を付けて保存することがあるため
    static func fields(_ text: String) -> (lines: [(line: Int, fields: [String])], problems: [Problem]) {
        var lines: [(line: Int, fields: [String])] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var lineNumber = 1
        var start = 1
        func endLine() {
            fields.append(field)
            if fields.contains(where: { !$0.isEmpty }) { lines.append((start, fields)) }
            fields = []
            field = ""
        }
        var characters = text.makeIterator()
        var pending = characters.next()
        while let c = pending {
            pending = characters.next()
            if quoted {
                if c == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        quoted = false
                    }
                } else {
                    if c.isNewline { lineNumber += 1 }
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == "," {
                fields.append(field)
                field = ""
            } else if c.isNewline {
                endLine()
                lineNumber += 1
                start = lineNumber
            } else {
                field.append(c)
            }
        }
        if quoted {
            return (lines, [Problem(line: start, message: "ダブルクォート「\"」が閉じていません")])
        }
        endLine()
        return (lines, [])
    }

    // MARK: - 保存する

    private struct ExerciseKey: Hashable {
        var name: String
        var part: Part
    }

    /// 名前と部位から引く、今ある種目。同じ名前と部位の種目が 2 つあるときは、先に作った種目に足す
    private static func exercises(_ db: Database) throws -> (target: [ExerciseKey: Exercise], keyById: [Int64: ExerciseKey]) {
        var target: [ExerciseKey: Exercise] = [:]
        var keyById: [Int64: ExerciseKey] = [:]
        for exercise in try Exercise.order(Column("id")).fetchAll(db) {
            let key = ExerciseKey(name: exercise.name, part: exercise.part)
            target[key] = target[key] ?? exercise
            keyById[exercise.id!] = key
        }
        return (target, keyById)
    }

    /// 読み込む前に、足す記録と新しく作る種目を決める。
    /// 名前と部位が同じ種目に、同じ日付と時刻(分まで)の記録が既にあれば、その記録は読み込まない。
    /// 同じ名前と部位の種目が 2 つあるときは、どちらの記録とも比べる
    static func plan(_ db: Database, _ records: [ImportRecord], timeZone: TimeZone) throws -> Plan {
        struct RecordKey: Hashable { var exercise: ExerciseKey; var at: LocalTime }
        let (target, keyById) = try exercises(db)
        let keys = Set(records.map { ExerciseKey(name: $0.exercise, part: $0.part) })
        let ids = keyById.filter { keys.contains($0.value) }.map(\.key)
        let existing = Set(try WorkoutRecord.filter(ids.contains(Column("exerciseId"))).fetchAll(db).map {
            RecordKey(exercise: keyById[$0.exerciseId]!, at: LocalTime($0))
        })

        var plan = Plan(records: [], skipped: 0, newExercises: [], hiddenExercises: [])
        var listed: Set<ExerciseKey> = []
        for record in records {
            let key = ExerciseKey(name: record.exercise, part: record.part)
            // 夏時間に切り替わって無い時刻は、保存する時刻で比べる。同じ CSV を 2 回読み込んでも重ならないように
            if existing.contains(RecordKey(exercise: key, at: record.at.saved(in: timeZone))) {
                plan.skipped += 1
                continue
            }
            plan.records.append(record)
            if listed.insert(key).inserted {
                let label = "\(key.name)(\(key.part.label))"
                if let exercise = target[key] {
                    if exercise.isHidden { plan.hiddenExercises.append(label) }
                } else {
                    plan.newExercises.append(label)
                }
            }
        }
        return plan
    }

    /// 記録を足す。足す記録は保存する時点の記録で決め直す。
    /// 日付と時刻は timeZone の時刻として読み、記録の時差もその日付の timeZone の時差にする
    @discardableResult
    static func save(_ db: Database, _ records: [ImportRecord], timeZone: TimeZone) throws -> Plan {
        let plan = try plan(db, records, timeZone: timeZone)
        var ids = try exercises(db).target.mapValues { $0.id! }
        for imported in plan.records {
            let key = ExerciseKey(name: imported.exercise, part: imported.part)
            let exerciseId: Int64
            if let id = ids[key] {
                exerciseId = id
            } else {
                var exercise = Exercise(name: imported.exercise, part: imported.part)
                try exercise.insert(db)
                exerciseId = exercise.id!
                ids[key] = exerciseId
            }
            var record = WorkoutRecord(exerciseId: exerciseId, performedAt: imported.at.date(in: timeZone), timeZone: timeZone, memo: imported.memo)
            try record.insert(db)
            for (i, set) in imported.sets.enumerated() {
                var set = set
                set.recordId = record.id!
                set.position = i
                try set.insert(db)
            }
        }
        return plan
    }

    // MARK: - 見本

    /// 読み込みの画面と見本の CSV に載せる行
    static let sampleLines: [[String]] = [
        CSVExport.header,
        ["ベンチプレス", "胸", "2026/11/01", "19:30", "1", "60", "10", "7", "", "フォームを確かめる"],
        ["ベンチプレス", "胸", "2026/11/01", "19:30", "2", "62.5", "8", "8", "", "フォームを確かめる"],
        ["懸垂", "背中", "2026/11/03", "7:15", "1", "0", "8", "", "2", ""],
    ]

    static var sample: String { CSVExport.text(sampleLines) }
}
