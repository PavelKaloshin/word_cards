import XCTest
import SwiftData
@testable import SerbianCards

final class AddWordsFlowTests: XCTestCase {

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

    func testWordCreationWithNormalization() throws {
        let (cyr, lat) = NormalizeService.toBoth("ljubav")
        XCTAssertEqual(cyr, "љубав")
        XCTAssertEqual(lat, "ljubav")

        let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: "love")
        context.insert(word)
        try context.save()

        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].wordCyr, "љубав")
        XCTAssertEqual(fetched[0].wordLat, "ljubav")
    }

    func testDeduplicationByNormalizedKey() throws {
        // Add first word
        let (cyr1, lat1) = NormalizeService.toBoth("kuća")
        let word1 = WordEntry(id: "w1", wordCyr: cyr1, wordLat: lat1)
        context.insert(word1)
        try context.save()

        // Check dedup: same word in Cyrillic should be detected
        let existingDescriptor = FetchDescriptor<WordEntry>()
        let existing = try context.fetch(existingDescriptor)
        let existingKeys = Set(existing.map { NormalizeService.normalizeForMatch($0.wordLat) })

        let newKey = NormalizeService.normalizeForMatch("кућа") // Cyrillic version
        XCTAssertTrue(existingKeys.contains(newKey), "Cyrillic version should match existing Latin word")

        // Different word should NOT match
        let differentKey = NormalizeService.normalizeForMatch("хлеб")
        XCTAssertFalse(existingKeys.contains(differentKey))
    }

    func testBatchWordCreation() throws {
        let wordsToAdd = ["хлеб", "вода", "кућа", "пас", "мачка"]
        var addedCount = 0

        for serbian in wordsToAdd {
            let (cyr, lat) = NormalizeService.toBoth(serbian)
            let word = WordEntry(wordCyr: cyr, wordLat: lat)
            context.insert(word)
            addedCount += 1
        }
        try context.save()

        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 5)
        XCTAssertEqual(addedCount, 5)
    }

    func testNaiveLineParsing() {
        let input = """
        хлеб | bread
        вода | water
        кућа
        """

        let lines = input.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let entries = lines.map { line -> (String, String) in
            let parts = line.split(separator: "|", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].0, "хлеб")
        XCTAssertEqual(entries[0].1, "bread")
        XCTAssertEqual(entries[2].0, "кућа")
        XCTAssertEqual(entries[2].1, "")
    }

    func testNaiveLineParsingStripsNumbering() {
        let numberPrefix = /^\d+[\.\)\-]\s*/

        let inputs = [
            "1. Я пишу ручкой.",
            "2) Он ест ложкой",
            "3- Мы режем ножом",
            "10. Она платит картой.",
            "хлеб | bread",
        ]

        let results = inputs.map { line in
            line.replacing(numberPrefix, with: "").trimmingCharacters(in: .whitespaces)
        }

        XCTAssertEqual(results[0], "Я пишу ручкой.")
        XCTAssertEqual(results[1], "Он ест ложкой")
        XCTAssertEqual(results[2], "Мы режем ножом")
        XCTAssertEqual(results[3], "Она платит картой.")
        XCTAssertEqual(results[4], "хлеб | bread")
    }
}
