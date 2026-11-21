import SwiftUI

/// 設定
struct SettingsView: View {
    @Environment(\.appDatabase) private var database
    @AppStorage(SettingsKey.intensity) private var intensity = IntensityKind.initial
    @AppStorage(SettingsKey.historyColumns) private var columnsRaw = HistoryColumn.initialRaw
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.initial
    @AppStorage(SettingsKey.showsElapsed) private var showsElapsed = ShowsElapsed.initial
    @State private var document: CSVDocument?
    @State private var isExporting = false

    private var columns: Set<HistoryColumn> { HistoryColumn.decode(columnsRaw) }

    var body: some View {
        Form {
            // アプリの全体に効くので、記録の入力欄や種目の履歴の表示項目より先に置く
            Section("外観") {
                ForEach(Appearance.allCases, id: \.self) { item in
                    Button {
                        appearance = item
                    } label: {
                        HStack(spacing: 12) {
                            AppearanceDot(appearance: item)
                            Text(item.label)
                                .foregroundStyle(Color.primary)
                            Spacer(minLength: 0)
                            if appearance == item {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(appearance == item ? .isSelected : [])
                }
            }
            Section("記録の入力欄") {
                Picker("強度", selection: $intensity) {
                    ForEach(IntensityKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Toggle("最後のセットからの経過時間", isOn: $showsElapsed)
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
                NavigationLink("データを読み込む (CSV)", value: Route.csvImport)
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
            if let columns = HistoryColumn.toggled(columns, column, isOn: isOn) {
                columnsRaw = HistoryColumn.encode(columns)
            }
        }
    }

    private struct AppearanceDot: View {
        let appearance: Appearance

        var body: some View {
            ZStack {
                Circle().fill(appearance == .dark ? Color.black : Color.white)
                if appearance == .system {
                    LowerRightHalf().fill(Color.black)
                }
            }
            .clipShape(Circle())
            .overlay { Circle().stroke(Color(.systemGray3), lineWidth: 1) }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        }
    }

    private struct LowerRightHalf: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
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
