import SwiftUI

@main
struct WorkoutLogApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                // App に置いた @AppStorage では、ダークの後に別の外観を選んでも画面がダークのまま変わらなかったので、ビューの中で読む
                .modifier(AppearanceModifier())
                .defaultAppStorage(Self.appStorage)
        }
    }

    // UI テストは、起動のたびに空の設定から始める。UI テストの各回を同じ条件で始めるためと、
    // 実際の設定が入ったシミュレーターで回しても設定を書き換えないため
    private static let appStorage: UserDefaults = {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return .standard }
        let suiteName = "uiTesting"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }()
}

/// 設定の外観を、ウィンドウに当てる
private struct AppearanceModifier: ViewModifier {
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.initial

    func body(content: Content) -> some View {
        content
            // preferredColorScheme は、nil に戻しても前の外観のまま残るので、ウィンドウの外観を直接変える
            .onChange(of: style, initial: true) { _, style in
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
    }

    private var style: UIUserInterfaceStyle {
        // UI テストは、起動引数「-uiTestingDark YES」でダークの外観にする。
        // シミュレーターの外観の設定は、変えてもアプリに届かないことがあるため
        if Self.isUITestingDark { return .dark }
        switch appearance {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    private static let isUITestingDark = UserDefaults.standard.bool(forKey: "uiTestingDark")
}
