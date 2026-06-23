import Foundation
import SwiftData

/// A single result entry within a session.
struct SessionResult: Codable, Equatable {
    let wordId: String
    let grade: String
    let direction: String
    let ts: String
}

/// Summary stats for a completed session.
struct SessionSummary: Codable, Equatable {
    let shown: Int
    let good: Int
    let hard: Int
    let again: Int
    let accuracy: Double
    let newMastered: Int
    let hardest: [HardestWord]
}

/// A word that appeared frequently with "again" grade in a session.
struct HardestWord: Codable, Equatable, Identifiable {
    let id: String
    let wordCyr: String
    let wordLat: String
    let againCount: Int
}

@Model
final class SessionRecord {
    @Attribute(.unique) var id: String
    var mode: String
    var startedAt: String
    var endedAt: String?
    var results: [SessionResult]
    var summary: SessionSummary

    init(
        id: String = UUID().uuidString,
        mode: String = "learn",
        startedAt: String = ISO8601DateFormatter().string(from: Date()),
        endedAt: String? = nil,
        results: [SessionResult] = [],
        summary: SessionSummary = SessionSummary(
            shown: 0, good: 0, hard: 0, again: 0,
            accuracy: 0, newMastered: 0, hardest: []
        )
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.results = results
        self.summary = summary
    }
}
