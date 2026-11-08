import SwiftUI
import UniformTypeIdentifiers

/// CSV の読み込み。ファイルを選ぶ前に列の書き方を見せ、読み込む前に足す内容を確かめさせる
struct CSVImportView: View {
    @Environment(\.appDatabase) private var database
    @State private var isImporting = false
    @State private var isExportingSample = false
    @State private var problems: [CSVImport.Problem] = []
    @State private var pending: Pending?
    @State private var message: String?

    struct Pending: Identifiable {
        let id = UUID()
        var records: [CSVImport.ImportRecord]
        var plan: CSVImport.Plan
    }

    private static let columns: [(name: String, rule: String)] = [
        ("種目", "種目の名前。名前と部位が同じ種目があればその種目に足し、無ければ種目を作る"),
        ("部位", Part.allCases.map(\.label).joined(separator: "・") + "のどれか"),
        ("日付", "2026/11/07 の形"),
        ("時刻", "19:30 の形(24 時間)。種目・部位・日付・時刻が同じ行は、1 回の記録にまとめる"),
        ("セット", "1 回の記録の中の順番。1 以上の整数"),
        ("重さ(kg)", "0 以上の数。小数も書ける"),
        ("回数", "1 以上の整数"),
        ("RPE", "空か、1〜10 の数"),
        ("RIR", "空か、0 以上の整数"),
        ("メモ", "空でもよい。同じ記録の行には、同じメモを書くか、1 行だけに書く"),
    ]

    var body: some View {
        Form {
            Section {
                Text("書き出す CSV と同じ列の CSV を読み込み、今ある記録に足します。同じ種目に同じ日付と時刻の記録が既にあれば、その記録は読み込みません。日付と時刻は、この端末のタイムゾーンの時刻として読みます。")
                    .font(.callout)
            }
            Section("列") {
                ForEach(Self.columns, id: \.name) { column in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.name)
                        Text(column.rule)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("例") {
                ScrollView(.horizontal) {
                    Text(CSVImport.sample.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines))
                        .font(.footnote.monospaced())
                        .fixedSize()
                        .padding(.vertical, 4)
                }
                Button("見本の CSV を書き出す") { isExportingSample = true }
                    .fileExporter(isPresented: $isExportingSample, document: CSVDocument(text: CSVImport.sample), contentType: .commaSeparatedText, defaultFilename: "workout-log-sample") { result in
                        if case .failure(let error) = result {
                            print("見本の CSV を書き出せない: \(error)")
                        }
                    }
            }
            Section {
                Button("ファイルを選んで読み込む") { isImporting = true }
                    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText], onCompletion: load)
            } footer: {
                if let message {
                    Text(message)
                }
            }
            if !problems.isEmpty {
                Section {
                    ForEach(problems, id: \.self) { problem in
                        Text(problem.text)
                            .font(.footnote)
                    }
                } header: {
                    Text("読み込めない行があります(\(problems.count))")
                        .foregroundStyle(.red)
                } footer: {
                    Text("どの行も読み込んでいません。直してから、もう一度読み込みます。")
                }
            }
        }
        .navigationTitle("CSV の読み込み")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { pending in
            CSVImportConfirmView(plan: pending.plan) {
                save(pending.records)
            }
        }
    }

    private func load(_ result: Result<URL, any Error>) {
        problems = []
        message = nil
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            switch CSVImport.records(try Data(contentsOf: url)) {
            case .failure(let failure):
                problems = failure.problems
            case .success(let records):
                let plan = try database.reader.read { try CSVImport.plan($0, records, timeZone: .current) }
                pending = Pending(records: records, plan: plan)
            }
        } catch {
            message = "ファイルを読めません: \(error.localizedDescription)"
        }
    }

    private func save(_ records: [CSVImport.ImportRecord]) {
        do {
            let plan = try database.writer.write { try CSVImport.save($0, records, timeZone: .current) }
            message = "記録 \(plan.records.count) 件・セット \(plan.setCount) 件を読み込みました。"
        } catch {
            message = "記録を保存できません: \(error.localizedDescription)"
        }
        pending = nil
    }
}

/// 読み込む前に、足す記録の数と新しく作る種目を確かめる
private struct CSVImportConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: CSVImport.Plan
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("足す記録", value: "\(plan.records.count) 件")
                    LabeledContent("足すセット", value: "\(plan.setCount) 件")
                    if plan.skipped > 0 {
                        LabeledContent("重なっていて読み込まない記録", value: "\(plan.skipped) 件")
                    }
                } footer: {
                    if plan.records.isEmpty {
                        Text("足す記録がありません。どの記録も、今ある記録と重なっています。")
                    }
                }
                if !plan.newExercises.isEmpty {
                    Section("新しく作る種目(\(plan.newExercises.count))") {
                        ForEach(plan.newExercises, id: \.self) { Text($0) }
                    }
                }
                if !plan.hiddenExercises.isEmpty {
                    Section {
                        ForEach(plan.hiddenExercises, id: \.self) { Text($0) }
                    } header: {
                        Text("記録を足す非表示の種目(\(plan.hiddenExercises.count))")
                    } footer: {
                        Text("ホームの「非表示の種目」の中にあります。")
                    }
                }
            }
            .navigationTitle("読み込む内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("読み込む", action: onImport)
                        .disabled(plan.records.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
