import XCTest
import SwiftData
@testable import SerbianCards

final class WordLifecycleTests: XCTestCase {

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

    func testFullWordLifecycle() throws {
        // 1. Create word
        let (cyr, lat) = NormalizeService.toBoth("кућа")
        let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: "house")
        context.insert(word)
        try context.save()

        // Verify persistence
        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].wordCyr, "кућа")
        XCTAssertEqual(fetched[0].wordLat, "kuća")

        // 2. Verify it starts as new
        XCTAssertTrue(word.isNew)

        // 3. Grade in learn session — streak increases
        let appConfig = AppConfig()
        context.insert(appConfig)

        ScoringService.applyGrade(word: word, grade: .good, config: appConfig)
        XCTAssertEqual(word.streak, 1)
        XCTAssertEqual(word.totalGood, 1)
        XCTAssertFalse(word.isNew)

        // 4. Grade again — streak grows
        ScoringService.applyGrade(word: word, grade: .good, config: appConfig)
        XCTAssertEqual(word.streak, 2)

        // 5. Grade good one more time — reaches mastered threshold (3)
        ScoringService.applyGrade(word: word, grade: .good, config: appConfig)
        XCTAssertEqual(word.streak, 3)
        XCTAssertTrue(ScoringService.isMastered(word: word, config: appConfig))

        // 6. Grade again after mastered — forget count increases
        ScoringService.applyGrade(word: word, grade: .again, config: appConfig)
        XCTAssertEqual(word.streak, 0)
        XCTAssertEqual(word.forgetCount, 1)
        XCTAssertFalse(ScoringService.isMastered(word: word, config: appConfig))

        // 7. Verify history
        XCTAssertEqual(word.history.count, 4)
    }

    func testWordEnrichmentFields() throws {
        let word = WordEntry(wordCyr: "хлеб", wordLat: "hleb")
        context.insert(word)

        // Simulate enrichment
        word.translation = "bread"
        word.exampleCyr = "Желим да купим хлеб."
        word.exampleLat = "Želim da kupim hleb."
        word.exampleTranslation = "I want to buy bread."
        try context.save()

        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched[0].translation, "bread")
        XCTAssertFalse(fetched[0].exampleCyr.isEmpty)
    }
}
