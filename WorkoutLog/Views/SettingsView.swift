import SwiftUI

/// 設定
struct SettingsView: View {
    @Environment(\.appDatabase) private var database
    @AppStorage(SettingsKey.intensity) private var intensity = IntensityKind.initial
    @AppStorage(SettingsKey.historyColumns) private var columnsRaw = HistoryColumn.initialRaw
    @State private var document: CSVDocument?
    @State private var isExporting = false

    private var columns: Set<HistoryColumn> { HistoryColumn.decode(columnsRaw) }

    var body: some View {
        Form {
            Section("記録の入力欄") {
                Picker("強度", selection: $intensity) {
                    ForEach(IntensityKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
            }
            Section {
                ForEach(HistoryColumn.allCases, id: \.self) { column in
                    Toggle(column.label, isOn: binding(column))
                        // 最後の 1 つは非表示にできない
                        .disabled(columns == [column])
                }
            } header: {
                Text("種目の履歴の表示項目")
            }
            Section("データ") {
                Button("データを書き出す (CSV)", action: export)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $isExporting, document: document, contentType: .commaSeparatedText, defaultFilename: "workout-log") { result in
            if case .failure(let error) = result {
                print("CSV を書き出せない: \(error)")
            }
        }
    }

    private func binding(_ column: HistoryColumn) -> Binding<Bool> {
        Binding {
            columns.contains(column)
        } set: { isOn in
            var columns = columns
            if isOn { columns.insert(column) } else { columns.remove(column) }
            if !columns.isEmpty {
                columnsRaw = HistoryColumn.encode(columns)
            }
        }
    }

    private func export() {
        do {
            document = CSVDocument(text: try database.reader.read(CSVExport.make))
            isExporting = true
        } catch {
            print("CSV を作れない: \(error)")
        }
    }
}
