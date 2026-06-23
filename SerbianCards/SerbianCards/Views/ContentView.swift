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
        }
    }
}
