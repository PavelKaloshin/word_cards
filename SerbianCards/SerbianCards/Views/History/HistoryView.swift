import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessions: [SessionRecord]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock",
                        description: Text("Complete a learn or review session to see your history.")
                    )
                } else {
                    List(sessions, id: \.id) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        appState.navigateTo(.home)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(session.startedAt))
                    .font(.subheadline)
                Spacer()
                Text(session.mode)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(session.mode == "learn" ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label("\(session.summary.shown)", systemImage: "eye")
                Label("\(Int(session.summary.accuracy * 100))%", systemImage: "target")
                if session.summary.newMastered > 0 {
                    Label("+\(session.summary.newMastered)", systemImage: "star.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = ScoringService.parseISO(isoString) else {
            return isoString.prefix(16).replacingOccurrences(of: "T", with: " ")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SessionDetailView: View {
    let session: SessionRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(label: "Shown", value: "\(session.summary.shown)")
                    statCard(label: "Correct", value: "\(session.summary.good + session.summary.hard)")
                    statCard(label: "Hard", value: "\(session.summary.hard)")
                    statCard(label: "Again", value: "\(session.summary.again)")
                    statCard(label: "Accuracy", value: "\(Int(session.summary.accuracy * 100))%")
                    statCard(label: "New Mastered", value: "\(session.summary.newMastered)")
                }
                .padding(.horizontal)

                // Hardest words
                if !session.summary.hardest.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hardest Words")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(session.summary.hardest) { word in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(word.wordCyr)
                                        .fontWeight(.medium)
                                    Text(word.wordLat)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(word.againCount)x again")
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.top)
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
