import SwiftUI

struct TypingInputView: View {
    @Environment(AppState.self) private var appState
    @State private var typedText: String = ""
    let word: WordEntry
    let config: AppConfig
    let onAutoGrade: (Grade) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Type the word...", text: $typedText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { checkTyping() }

                Button("Check") { checkTyping() }
                    .buttonStyle(.borderedProminent)
            }

            if let result = appState.typingResult {
                HStack {
                    if result.distance == 0 {
                        Label("Correct!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if result.suggestedGrade == .hard {
                        Label("Close (distance \(result.distance))", systemImage: "minus.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Expected: \(result.expectedLat)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Expected: \(result.expectedLat)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("(\(result.expectedCyr))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
    }

    private func checkTyping() {
        guard !typedText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let relaxed = config.typingRelaxedDiacritics
        let normTyped = NormalizeService.normalizeForMatch(typedText, relaxedDiacritics: relaxed)
        let normTarget = NormalizeService.normalizeForMatch(word.wordLat, relaxedDiacritics: relaxed)
        let distance = LevenshteinService.distance(normTyped, normTarget)
        let threshold = config.typingHardLevenshteinThreshold

        let suggestedGrade: Grade
        if distance == 0 {
            suggestedGrade = .good
        } else if distance <= threshold {
            suggestedGrade = .hard
        } else {
            suggestedGrade = .again
        }

        appState.typingResult = TypingCheckResult(
            distance: distance,
            suggestedGrade: suggestedGrade,
            expectedCyr: word.wordCyr,
            expectedLat: word.wordLat
        )

        // Auto-flip to show the answer
        if !appState.isFlipped {
            appState.isFlipped = true
        }
    }
}
