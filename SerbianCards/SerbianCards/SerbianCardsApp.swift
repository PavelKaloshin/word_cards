import SwiftUI
import SwiftData

@main
struct SerbianCardsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            WordEntry.self,
            AppConfig.self,
            SessionRecord.self,
        ])
    }
}
