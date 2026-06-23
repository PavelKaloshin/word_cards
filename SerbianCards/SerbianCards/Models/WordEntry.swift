import Foundation
import SwiftData

/// A single answer record stored in the word's history.
struct AnswerRecord: Codable, Equatable {
    let ts: String
    let grade: String
    let direction: String
}

@Model
final class WordEntry {
    @Attribute(.unique) var id: String
    var wordCyr: String
    var wordLat: String
    var translation: String
    var exampleCyr: String
    var exampleLat: String
    var exampleTranslation: String
    var imagePath: String
    var audioPath: String
    var imageHashHistory: [String]
    var note: String
    var createdAt: String
    var lastSeenAt: String?
    var lastCorrectAt: String?
    var streak: Int
    var totalGood: Int
    var totalHard: Int
    var totalAgain: Int
    var forgetCount: Int
    var history: [AnswerRecord]

    init(
        id: String = UUID().uuidString,
        wordCyr: String = "",
        wordLat: String = "",
        translation: String = "",
        exampleCyr: String = "",
        exampleLat: String = "",
        exampleTranslation: String = "",
        imagePath: String = "",
        audioPath: String = "",
        imageHashHistory: [String] = [],
        note: String = "",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        lastSeenAt: String? = nil,
        lastCorrectAt: String? = nil,
        streak: Int = 0,
        totalGood: Int = 0,
        totalHard: Int = 0,
        totalAgain: Int = 0,
        forgetCount: Int = 0,
        history: [AnswerRecord] = []
    ) {
        self.id = id
        self.wordCyr = wordCyr
        self.wordLat = wordLat
        self.translation = translation
        self.exampleCyr = exampleCyr
        self.exampleLat = exampleLat
        self.exampleTranslation = exampleTranslation
        self.imagePath = imagePath
        self.audioPath = audioPath
        self.imageHashHistory = imageHashHistory
        self.note = note
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.lastCorrectAt = lastCorrectAt
        self.streak = streak
        self.totalGood = totalGood
        self.totalHard = totalHard
        self.totalAgain = totalAgain
        self.forgetCount = forgetCount
        self.history = history
    }

    /// Total number of attempts across all grades.
    var totalAttempts: Int {
        totalGood + totalHard + totalAgain
    }

    /// Whether this word has never been graded.
    var isNew: Bool {
        totalAttempts == 0
    }
}
