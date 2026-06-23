import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [WordEntry]

    // Swipe gesture state
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // HUD
            let hud = currentHUD
            HUDView(hud: hud)

            // Learn progress strip (learn mode only)
            if appState.activeSession?.mode == .learn, let progress = appState.learnProgress {
                LearnProgressView(progress: progress)
                    .padding(.top, 4)
                    .onTapGesture {
                        appState.learnPanelOpen.toggle()
                    }
            }

            // Learn panel (expandable)
            if appState.learnPanelOpen, let progress = appState.learnProgress {
                LearnPanelView(progress: progress)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            // Card
            if let word = appState.currentWord {
                CardView(word: word)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .padding(.horizontal)
                    .offset(x: dragOffset.width)
                    .gesture(swipeGesture)

                // Typing input (front side only, when typing mode is on)
                if appState.typingMode && !appState.isFlipped {
                    TypingInputView(
                        word: word,
                        config: loadConfig(),
                        onAutoGrade: { grade in gradeCurrentWord(grade) }
                    )
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Toolbar
            toolbar

            // Grade buttons (only when flipped)
            if appState.isFlipped {
                GradeButtonsView { grade in
                    gradeCurrentWord(grade)
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isFlipped)
        .onAppear { updateLearnProgress() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            toolbarButton(systemImage: "speaker.wave.2", label: "Speak") {
                TTSService.shared.speak(appState.currentWord?.wordCyr ?? "")
            }
            toolbarButton(
                systemImage: "character.book.closed",
                label: "Translation",
                isActive: appState.showTranslation
            ) {
                appState.showTranslation.toggle()
            }
            toolbarButton(
                systemImage: "text.quote",
                label: "Example",
                isActive: appState.showExample
            ) {
                appState.showExample.toggle()
            }
            toolbarButton(systemImage: "textformat.abc", label: "Alphabet") {
                appState.alphabet = appState.alphabet.next
                appState.showToast("Alphabet: \(appState.alphabet.rawValue)")
            }
            toolbarButton(
                systemImage: "keyboard",
                label: "Type",
                isActive: appState.typingMode
            ) {
                appState.typingMode.toggle()
            }
            Spacer()
            toolbarButton(systemImage: "xmark.circle", label: "Exit") {
                exitSession()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func toolbarButton(
        systemImage: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Swipe gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height

                withAnimation(.spring()) {
                    dragOffset = .zero
                }

                // Threshold for activation
                let threshold: CGFloat = 80

                if abs(horizontalAmount) > abs(verticalAmount) {
                    if horizontalAmount < -threshold {
                        // Swipe left -> Again
                        gradeCurrentWord(.again)
                    } else if horizontalAmount > threshold {
                        // Swipe right -> Good
                        gradeCurrentWord(.good)
                    }
                } else if verticalAmount < -threshold {
                    // Swipe up -> Hard
                    gradeCurrentWord(.hard)
                }
            }
    }

    // MARK: - Actions

    private func gradeCurrentWord(_ grade: Grade) {
        guard let session = appState.activeSession else { return }
        let config = loadConfig()

        // Haptic feedback
        let feedbackGenerator = UINotificationFeedbackGenerator()
        switch grade {
        case .good: feedbackGenerator.notificationOccurred(.success)
        case .hard: feedbackGenerator.notificationOccurred(.warning)
        case .again: feedbackGenerator.notificationOccurred(.error)
        }

        let wordLookup: (String) -> WordEntry? = { id in
            words.first { $0.id == id }
        }

        SessionService.answer(
            session: session,
            grade: grade,
            config: config,
            wordLookup: wordLookup,
            saveWord: { _ in
                try? modelContext.save()
            }
        )

        // Update state
        appState.resetSessionState()
        appState.typingMode = config.typingModeEnabled

        if let currentCard = session.current {
            appState.currentWord = words.first { $0.id == currentCard.wordId }
        } else {
            appState.currentWord = nil
            finishSession()
        }

        updateLearnProgress()
    }

    private func updateLearnProgress() {
        guard let session = appState.activeSession, session.mode == .learn else {
            appState.learnProgress = nil
            return
        }
        let config = loadConfig()
        let wordLookup: (String) -> WordEntry? = { id in
            words.first { $0.id == id }
        }
        appState.learnProgress = SessionService.computeLearnProgress(
            session: session,
            config: config,
            wordLookup: wordLookup
        )
    }

    private func exitSession() {
        guard let session = appState.activeSession else {
            appState.navigateTo(.home)
            return
        }
        finishSessionAndNavigate(session)
    }

    private func finishSession() {
        guard let session = appState.activeSession else {
            appState.navigateTo(.home)
            return
        }
        finishSessionAndNavigate(session)
    }

    private func finishSessionAndNavigate(_ session: ActiveSession) {
        SessionService.end(session)

        let wordLookup: (String) -> WordEntry? = { id in
            words.first { $0.id == id }
        }
        let (summary, results) = SessionService.toSummary(session: session, wordLookup: wordLookup)

        // Save SessionRecord
        let record = SessionRecord(
            id: session.id,
            mode: session.mode.rawValue,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            results: results,
            summary: summary
        )
        modelContext.insert(record)
        try? modelContext.save()

        appState.sessionSummary = summary
        appState.sessionMode = session.mode
        appState.activeSession = nil
        appState.currentWord = nil
        appState.navigateTo(.sessionEnd)
    }

    private var currentHUD: SessionHUD {
        guard let session = appState.activeSession else {
            return SessionHUD()
        }
        return SessionService.hud(session: session)
    }

    private func loadConfig() -> AppConfig {
        let descriptor = FetchDescriptor<AppConfig>()
        return (try? modelContext.fetch(descriptor))?.first ?? AppConfig()
    }
}
