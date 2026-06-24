import XCTest
import SwiftData
@testable import SerbianCards

final class ConfigPersistenceTests: XCTestCase {

    func testConfigDefaultValues() throws {
        let schema = Schema([WordEntry.self, AppConfig.self, SessionRecord.self])
        let modelConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfig])
        let context = ModelContext(container)

        let config = AppConfig()
        context.insert(config)
        try context.save()

        // Fetch in new context
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<AppConfig>()
        let fetched = try context2.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].masteredThreshold, 3)
        XCTAssertEqual(fetched[0].reviewSessionSize, 100)
        XCTAssertEqual(fetched[0].hardModifier, 0.5)
        XCTAssertEqual(fetched[0].reverseProbability, 0.5)
    }

    func testConfigModificationPersists() throws {
        let schema = Schema([WordEntry.self, AppConfig.self, SessionRecord.self])
        let modelConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfig])
        let context = ModelContext(container)

        let config = AppConfig()
        context.insert(config)
        try context.save()

        // Modify values
        config.masteredThreshold = 5
        config.reviewSessionSize = 50
        config.typingModeEnabled = true
        try context.save()

        // Verify in new context
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<AppConfig>()
        let fetched = try context2.fetch(descriptor)
        XCTAssertEqual(fetched[0].masteredThreshold, 5)
        XCTAssertEqual(fetched[0].reviewSessionSize, 50)
        XCTAssertTrue(fetched[0].typingModeEnabled)
    }

    func testConfigAffectsScoringBehavior() throws {
        let schema = Schema([WordEntry.self, AppConfig.self, SessionRecord.self])
        let modelConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfig])
        let context = ModelContext(container)

        let config = AppConfig()
        context.insert(config)
        let word = WordEntry(id: "test", wordCyr: "тест", wordLat: "test", streak: 3, totalGood: 3)
        context.insert(word)
        try context.save()

        // With default threshold (3), word is mastered
        XCTAssertTrue(ScoringService.isMastered(word: word, config: config))

        // Change threshold to 5
        config.masteredThreshold = 5
        try context.save()

        // Now the same word is NOT mastered
        XCTAssertFalse(ScoringService.isMastered(word: word, config: config))
    }
}
