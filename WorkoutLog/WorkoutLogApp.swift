import SwiftUI

@main
struct WorkoutLogApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
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
