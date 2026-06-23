import SwiftUI

struct SessionEndView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let summary = appState.sessionSummary {
                        // Stats grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 12) {
                            summaryCard(label: "Shown", value: "\(summary.shown)", color: .primary)
                            summaryCard(label: "Correct", value: "\(summary.good + summary.hard)", color: .green)
                            summaryCard(label: "Hard", value: "\(summary.hard)", color: .orange)
                            summaryCard(label: "Again", value: "\(summary.again)", color: .red)
                            summaryCard(label: "Accuracy", value: "\(Int(summary.accuracy * 100))%", color: .blue)
                            summaryCard(label: "New Mastered", value: "\(summary.newMastered)", color: .green)
                        }
                        .padding(.horizontal)

                        // Hardest words
                        if !summary.hardest.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Hardest Words")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(summary.hardest) { word in
                                    HStack {
                                        Text(word.wordCyr)
                                            .fontWeight(.medium)
                                        Text("/ \(word.wordLat)")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(word.againCount)x")
                                            .foregroundStyle(.red)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            appState.navigateTo(.home)
                        } label: {
                            Text("Another Session")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            appState.sessionSummary = nil
                            appState.navigateTo(.home)
                        } label: {
                            Text("Home")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func summaryCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
