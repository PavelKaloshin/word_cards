import Foundation
import SwiftData

/// A single answer record stored in the word's history.
struct AnswerRecord: Codable, Equatable {
    let ts: String
    let grade: String
    let direction: String
}

struct ConjugationForm: Codable, Equatable {
    let cyr: String
    let lat: String
}

struct ConjugationTable: Codable, Equatable {
    let sg1: ConjugationForm
    let sg2: ConjugationForm
    let sg3: ConjugationForm
    let pl1: ConjugationForm
    let pl2: ConjugationForm
    let pl3: ConjugationForm
}

@Model
final class WordEntry {
    @Attribute(.unique) var id: String = UUID().uuidString
    var wordCyr: String = ""
    var wordLat: String = ""
    var translation: String = ""
    var exampleCyr: String = ""
    var exampleLat: String = ""
    var exampleTranslation: String = ""
    var imagePath: String = ""
    var audioPath: String = ""
    var imageHashHistory: [String] = []
    var note: String = ""
    var createdAt: String = ISO8601DateFormatter().string(from: Date())
    var lastSeenAt: String?
    var lastCorrectAt: String?
    var streak: Int = 0
    var totalGood: Int = 0
    var totalHard: Int = 0
    var totalAgain: Int = 0
    var forgetCount: Int = 0
    var history: [AnswerRecord] = []
    var pos: String = ""
    var verbGroup: String = ""
    var conjugations: ConjugationTable?

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
        history: [AnswerRecord] = [],
        pos: String = "",
        verbGroup: String = "",
        conjugations: ConjugationTable? = nil
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
        self.pos = pos
        self.verbGroup = verbGroup
        self.conjugations = conjugations
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
