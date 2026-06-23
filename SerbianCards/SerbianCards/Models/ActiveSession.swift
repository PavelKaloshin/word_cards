import Foundation

/// Represents the current card being displayed in a session.
struct CurrentCard: Equatable {
    let wordId: String
    let direction: Direction
}

/// Live HUD data displayed during a session.
struct SessionHUD: Equatable {
    var good: Int = 0
    var hard: Int = 0
    var again: Int = 0
    var accuracy: Double = 0.0
    var position: Int = 0
    var total: Int = 0
    var mode: SessionMode = .learn
}

/// Per-word progress info for the learn-mode progress strip.
struct LearnProgressItem: Identifiable {
    let id: String
    let wordCyr: String
    let wordLat: String
    let translation: String
    let imagePath: String
    var correctCount: Int
    var streak: Int
    var completed: Bool
}

/// Aggregate learn progress data.
struct LearnProgress {
    let threshold: Int
    var totalCorrect: Int
    var maxCorrect: Int
    var completedWords: Int
    var remainingWords: Int
    var totalWords: Int
    var words: [LearnProgressItem]
}

/// In-memory session state. Not persisted to SwiftData — session is lost if app is killed.
final class ActiveSession {
    let id: String
    let mode: SessionMode
    let startedAt: String
    var endedAt: String?
    var queue: [String] // word IDs
    var reviewResults: [SessionResult] = []
    var current: CurrentCard?
    var newMasteredIds: Set<String> = []
    var learnInitialTotal: Int = 0
    var learnWordIds: [String] = []
    var learnCorrectCount: [String: Int] = [:]

    // Cumulative HUD counters
    var goodCount: Int = 0
    var hardCount: Int = 0
    var againCount: Int = 0

    init(
        id: String = UUID().uuidString,
        mode: SessionMode,
        startedAt: String = ISO8601DateFormatter().string(from: Date()),
        queue: [String] = []
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.queue = queue
    }
}
