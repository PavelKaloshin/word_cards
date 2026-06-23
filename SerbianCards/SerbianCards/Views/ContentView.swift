import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            switch appState.currentScreen {
            case .apiKeyEntry:
                APIKeyEntryView()
            case .home:
                HomeView()
            case .session:
                SessionView()
            case .sessionEnd:
                SessionEndView()
            case .addWords:
                AddWordsView()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            }

            // Toast overlay
            if let toast = appState.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            appState.toastMessage = nil
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toastMessage != nil)
        .onAppear {
            ensureConfig()
            if !KeychainService.hasAPIKey() {
                appState.navigateTo(.apiKeyEntry)
            }
        }
    }

    private func ensureConfig() {
        let descriptor = FetchDescriptor<AppConfig>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        if existing.isEmpty {
            let config = AppConfig()
            modelContext.insert(config)
            try? modelContext.save()
        } else if let config = existing.first {
            migrateStaleModelNames(config)
        }
    }

    private static let modelRenames: [String: String] = [
        "gpt-4o-mini": "gpt-5.4-mini",
        "gpt-4o": "gpt-5.4",
        "gpt-4-turbo": "gpt-4.1",
        "gpt-4": "gpt-4.1",
        "dall-e-3": "gpt-image-2",
    ]

    private func migrateStaleModelNames(_ config: AppConfig) {
        var changed = false
        for (old, new) in Self.modelRenames {
            if config.openaiModelText == old { config.openaiModelText = new; changed = true }
            if config.openaiModelVision == old { config.openaiModelVision = new; changed = true }
            if config.openaiModelExtract == old { config.openaiModelExtract = new; changed = true }
            if config.openaiModelImage == old { config.openaiModelImage = new; changed = true }
        }
        if changed { try? modelContext.save() }
    }
}
