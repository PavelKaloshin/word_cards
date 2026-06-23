import SwiftUI

struct CardView: View {
    @Environment(AppState.self) private var appState
    let word: WordEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))

            if appState.isFlipped {
                backSide
            } else {
                frontSide
            }
        }
        .rotation3DEffect(
            .degrees(appState.isFlipped ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .animation(.easeInOut(duration: 0.4), value: appState.isFlipped)
        .onTapGesture {
            if !appState.isFlipped {
                flipCard()
            }
        }
    }

    private var frontSide: some View {
        VStack(spacing: 16) {
            // Image
            wordImage

            // Direction-dependent front display
            if appState.activeSession?.current?.direction == .reverse {
                // Reverse: show Serbian word, user guesses translation
                wordText
            } else {
                // Forward: show translation, user guesses word
                Text(word.translation.isEmpty ? "(no translation)" : word.translation)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var backSide: some View {
        VStack(spacing: 12) {
            // Image
            wordImage

            // Serbian word
            wordText

            // Translation
            if appState.showTranslation || appState.activeSession?.current?.direction == .forward {
                Text(word.translation.isEmpty ? "(no translation)" : word.translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Example
            if appState.showExample {
                VStack(spacing: 4) {
                    Text(exampleForAlphabet())
                        .font(.subheadline)
                        .italic()
                        .multilineTextAlignment(.center)
                    if !word.exampleTranslation.isEmpty {
                        Text(word.exampleTranslation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 20)
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
    }

    @ViewBuilder
    private var wordImage: some View {
        if let image = MediaStorageService.loadImage(path: word.imagePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
    }

    private var wordText: some View {
        VStack(spacing: 4) {
            switch appState.alphabet {
            case .cyr:
                Text(word.wordCyr)
                    .font(.title)
                    .fontWeight(.bold)
            case .lat:
                Text(word.wordLat)
                    .font(.title)
                    .fontWeight(.bold)
            case .both:
                Text(word.wordCyr)
                    .font(.title)
                    .fontWeight(.bold)
                Text(word.wordLat)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    private func exampleForAlphabet() -> String {
        switch appState.alphabet {
        case .cyr: return word.exampleCyr
        case .lat: return word.exampleLat
        case .both:
            var result = word.exampleCyr
            if !word.exampleLat.isEmpty {
                result += "\n" + word.exampleLat
            }
            return result
        }
    }

    private func flipCard() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        appState.isFlipped = true
    }
}
