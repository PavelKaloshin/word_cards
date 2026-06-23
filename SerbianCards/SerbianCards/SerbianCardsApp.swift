import SwiftUI
import SwiftData

@main
struct SerbianCardsApp: App {
    @State private var appState = AppState()

    let container: ModelContainer

    init() {
        let schema = Schema([WordEntry.self, AppConfig.self, SessionRecord.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Migration failed — delete corrupt store and retry
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appending(path: "default.store\(ext)"))
            }
            container = try! ModelContainer(for: schema)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
