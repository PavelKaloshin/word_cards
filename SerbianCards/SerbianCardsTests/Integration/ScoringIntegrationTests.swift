import XCTest
import SwiftData
@testable import SerbianCards

final class ScoringIntegrationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([WordEntry.self, AppConfig.self, SessionRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    func testIntervalProgressionWithRepeatedGrades() throws {
        let config = AppConfig()
        context.insert(config)
        let word = WordEntry(id: "test", wordCyr: "тест", wordLat: "test")
        context.insert(word)
        try context.save()

        // Grade good repeatedly — intervals should increase
        var previousInterval: Double = 0
        for i in 0..<5 {
            ScoringService.applyGrade(word: word, grade: .good, config: config)
            let interval = ScoringService.effectiveIntervalMinutes(word: word, config: config)
            XCTAssertGreaterThan(interval, previousInterval, "Interval should grow at streak \(i + 1)")
            previousInterval = interval
        }

        // Grade again — streak resets, interval drops
        ScoringService.applyGrade(word: word, grade: .again, config: config)
        let afterAgain = ScoringService.effectiveIntervalMinutes(word: word, config: config)
        XCTAssertLessThan(afterAgain, previousInterval)
    }

    func testForgetCountDecaysInterval() throws {
        let config = AppConfig()
        context.insert(config)

        let word1 = WordEntry(id: "w1", wordCyr: "а", wordLat: "a", streak: 3, totalGood: 3)
        let word2 = WordEntry(id: "w2", wordCyr: "б", wordLat: "b", streak: 3, totalGood: 3, forgetCount: 2)
        context.insert(word1)
        context.insert(word2)
        try context.save()

        let iv1 = ScoringService.effectiveIntervalMinutes(word: word1, config: config)
        let iv2 = ScoringService.effectiveIntervalMinutes(word: word2, config: config)
        XCTAssertLessThan(iv2, iv1, "More forgettings should result in shorter interval")
    }

    func testWeightedSamplingPrefersOverdueWords() throws {
        let config = AppConfig()
        context.insert(config)

        // Word seen very long ago (very overdue)
        let overdue = WordEntry(
            id: "overdue", wordCyr: "а", wordLat: "a",
            lastSeenAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-999999 * 60)),
            totalGood: 1, totalAgain: 5
        )
        // Word seen recently (not due)
        let recent = WordEntry(
            id: "recent", wordCyr: "б", wordLat: "b",
            lastSeenAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)),
            totalGood: 10
        )
        context.insert(overdue)
        context.insert(recent)
        try context.save()

        // Run sampling many times — overdue word should be picked far more often
        var overduePickCount = 0
        for _ in 0..<200 {
            let picks = ScoringService.pickReviewWords(words: [overdue, recent], config: config, n: 1)
            if picks.first?.id == "overdue" {
                overduePickCount += 1
            }
        }
        XCTAssertGreaterThan(overduePickCount, 100, "Overdue + high-error word should be picked most of the time")
    }

    func testDueDetectionMatchesIntervals() throws {
        let config = AppConfig()
        context.insert(config)

        // Word at streak=1, interval=1440 min (1 day)
        // Last seen 2 days ago -> should be due
        let due = WordEntry(
            id: "due", wordCyr: "а", wordLat: "a",
            lastSeenAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2 * 24 * 3600)),
            streak: 1, totalGood: 1
        )
        // Last seen 1 hour ago -> should not be due
        let notDue = WordEntry(
            id: "notDue", wordCyr: "б", wordLat: "b",
            lastSeenAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
            streak: 1, totalGood: 1
        )
        context.insert(due)
        context.insert(notDue)
        try context.save()

        let now = Date()
        XCTAssertTrue(ScoringService.isDue(word: due, config: config, now: now))
        XCTAssertFalse(ScoringService.isDue(word: notDue, config: config, now: now))
    }
}
