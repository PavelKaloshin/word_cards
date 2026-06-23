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

    /// Replicates the exact save flow from AddWordsView:
    /// insert skeletons → save → verify fetch → simulate navigating to HomeView
    func testSkeletonSavePersistsAcrossContexts() throws {
        // Step 1: Insert skeletons (same as saveSelectedWords)
        let words = ["ljubav", "kuća", "hleb"]
        var inserted: [WordEntry] = []
        for w in words {
            let (cyr, lat) = NormalizeService.toBoth(w)
            let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: "")
            context.insert(word)
            inserted.append(word)
        }

        // Verify pending state
        XCTAssertTrue(context.hasChanges, "Context should have pending changes after insert")
        XCTAssertEqual(context.insertedModelsArray.count, 3, "Should have 3 pending inserts")

        // Step 2: Save
        try context.save()

        // Step 3: Fetch from SAME context (what AddWordsView does for verification)
        let sameContextCount = try context.fetch(FetchDescriptor<WordEntry>()).count
        XCTAssertEqual(sameContextCount, 3, "Same context should see 3 words after save")

        // Step 4: Fetch from a NEW context (simulates HomeView's @Query using a different context)
        let otherContext = ModelContext(container)
        let otherContextCount = try otherContext.fetch(FetchDescriptor<WordEntry>()).count
        XCTAssertEqual(otherContextCount, 3, "New context should also see 3 words after save")
    }

    /// Test using container.mainContext (what @Environment(\.modelContext) provides)
    @MainActor
    func testSkeletonSaveViaMainContext() throws {
        let mainCtx = container.mainContext

        let words = ["ljubav", "kuća", "hleb"]
        for w in words {
            let (cyr, lat) = NormalizeService.toBoth(w)
            let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: "")
            mainCtx.insert(word)
        }

        let pendingInserts = mainCtx.insertedModelsArray.count
        XCTAssertEqual(pendingInserts, 3, "mainContext should have 3 pending inserts")

        try mainCtx.save()

        let count = try mainCtx.fetch(FetchDescriptor<WordEntry>()).count
        XCTAssertEqual(count, 3, "mainContext should see 3 words after save")

        // Also verify from a separate context
        let freshCtx = ModelContext(container)
        let freshCount = try freshCtx.fetch(FetchDescriptor<WordEntry>()).count
        XCTAssertEqual(freshCount, 3, "Fresh context should see 3 words persisted by mainContext")
    }

    /// Test saving from async Task (replicates Task { await saveSelectedWords() })
    @MainActor
    func testSkeletonSaveFromAsyncTask() async throws {
        let mainCtx = container.mainContext

        // Simulate the Task-based save flow
        let words = ["ljubav", "kuća"]
        for w in words {
            let (cyr, lat) = NormalizeService.toBoth(w)
            let word = WordEntry(wordCyr: cyr, wordLat: lat, translation: "")
            mainCtx.insert(word)
        }
        try mainCtx.save()

        let count = try mainCtx.fetch(FetchDescriptor<WordEntry>()).count
        XCTAssertEqual(count, 2, "Words should persist when saved from async context")
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
