import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [WordEntry]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Stats cards
                    HStack(spacing: 16) {
                        StatCard(title: "New", value: "\(appState.statsNew)", color: .blue)
                        StatCard(title: "Due", value: "\(appState.statsDue)", color: .orange)
                        StatCard(title: "Total", value: "\(appState.statsTotal)", color: .gray)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        StatCard(title: "Mastered", value: "\(appState.statsMastered)", color: .green)
                        Spacer()
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            startSession(mode: .learn)
                        } label: {
                            Label("Learn New Words", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.statsNew == 0)

                        Button {
                            startSession(mode: .review)
                        } label: {
                            Label("Review", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(appState.statsTotal - appState.statsNew == 0)

                        HStack(spacing: 12) {
                            Button {
                                appState.navigateTo(.addWords)
                            } label: {
                                Label("Add Words", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                appState.navigateTo(.history)
                            } label: {
                                Label("History", systemImage: "clock.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            appState.navigateTo(.settings)
                        } label: {
                            Label("Settings", systemImage: "gearshape.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Serbian Cards")
            .onAppear { loadStats() }
        }
    }

    private func loadStats() {
        let config = loadConfig()
        let now = Date()
        var newCount = 0
        var dueCount = 0
        var masteredCount = 0
        for word in words {
            if word.isNew {
                newCount += 1
            } else if ScoringService.isDue(word: word, config: config, now: now) {
                dueCount += 1
            }
            if ScoringService.isMastered(word: word, config: config) {
                masteredCount += 1
            }
        }
        appState.statsNew = newCount
        appState.statsDue = dueCount
        appState.statsTotal = words.count
        appState.statsMastered = masteredCount
    }

    private func startSession(mode: SessionMode) {
        let config = loadConfig()
        let session: ActiveSession
        if mode == .learn {
            session = SessionService.startLearnSession(words: Array(words), config: config)
        } else {
            session = SessionService.startReviewSession(words: Array(words), config: config)
        }

        guard session.current != nil else {
            appState.showToast("No words available for this session")
            return
        }

        appState.activeSession = session
        appState.resetSessionState()
        appState.typingMode = config.typingModeEnabled
        if let currentCard = session.current {
            appState.currentWord = words.first { $0.id == currentCard.wordId }
        }
        appState.navigateTo(.session)
    }

    private func loadConfig() -> AppConfig {
        let descriptor = FetchDescriptor<AppConfig>()
        return (try? modelContext.fetch(descriptor))?.first ?? AppConfig()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
