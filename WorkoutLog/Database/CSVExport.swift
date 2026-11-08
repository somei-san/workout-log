import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// すべてのセットを、1 セット 1 行の CSV にする
enum CSVExport {
    static let header = ["種目", "部位", "日付", "時刻", "セット", "重さ(kg)", "回数", "RPE", "RIR", "メモ"]

    static func make(_ db: Database) throws -> String {
        let exercises = Dictionary(uniqueKeysWithValues: try Exercise.fetchAll(db).map { ($0.id!, $0) })
        let records = try WorkoutRecord.order(Column("performedAt"), Column("id")).fetchAll(db)
        let setsByRecord = Dictionary(grouping: try WorkoutSet.order(Column("position")).fetchAll(db), by: \.recordId)
        var lines = [header]
        for record in records {
            guard let exercise = exercises[record.exerciseId] else { continue }
            let (date, time) = dateAndTime(record)
            for (i, set) in (setsByRecord[record.id!] ?? []).enumerated() {
                lines.append([
                    exercise.name, exercise.part.label, date, time, "\(i + 1)",
                    Format.weight(set.weight), "\(set.reps)",
                    set.rpe.map(Format.weight) ?? "", set.rir.map(String.init) ?? "", record.memo,
                ])
            }
        }
        return text(lines)
    }

    /// 記録した場所の時刻での、記録の日付(2026/11/07)と時刻(19:30)
    static func dateAndTime(_ record: WorkoutRecord) -> (date: String, time: String) {
        let dateTime = Format.date(record.performedAt, timeZone: record.timeZone, time: true)
        return (String(dateTime.prefix(10)), String(dateTime.suffix(5)))
    }

    static func text(_ lines: [[String]]) -> String {
        lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// カンマ・ダブルクォート・改行を含む値は、ダブルクォートで囲む
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// 書き出す CSV のファイル
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Excel で開いたときに文字化けしないよう、UTF-8 の BOM を付ける
        FileWrapper(regularFileWithContents: Data("\u{FEFF}".utf8) + Data(text.utf8))
    }
}
