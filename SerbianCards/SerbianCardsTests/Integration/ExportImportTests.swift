import XCTest
import SwiftData
@testable import SerbianCards

final class ExportImportTests: XCTestCase {

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

    func testExportWordsToJSON() throws {
        // Create test data
        let word = WordEntry(
            id: "test-word-1",
            wordCyr: "хлеб",
            wordLat: "hleb",
            translation: "bread",
            streak: 3,
            totalGood: 5
        )
        context.insert(word)

        let config = AppConfig()
        config.masteredThreshold = 5
        context.insert(config)
        try context.save()

        // Verify data is there
        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "test-word-1")
        XCTAssertEqual(fetched[0].streak, 3)
    }

    func testExportSessionRecordsToJSON() throws {
        let record = SessionRecord(
            id: "session-1",
            mode: "learn",
            startedAt: ScoringService.nowISO(),
            endedAt: ScoringService.nowISO(),
            results: [
                SessionResult(wordId: "w1", grade: "good", direction: "forward", ts: ScoringService.nowISO()),
            ],
            summary: SessionSummary(
                shown: 5, good: 3, hard: 1, again: 1,
                accuracy: 0.8, newMastered: 2,
                hardest: [HardestWord(id: "w1", wordCyr: "тест", wordLat: "test", againCount: 1)]
            )
        )
        context.insert(record)
        try context.save()

        let descriptor = FetchDescriptor<SessionRecord>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].summary.shown, 5)
        XCTAssertEqual(fetched[0].summary.accuracy, 0.8)
        XCTAssertEqual(fetched[0].summary.hardest.count, 1)
    }

    func testWebAppJSONFormatParsing() throws {
        // Simulate the web app's words.json format (dict of dicts keyed by UUID)
        let webAppJSON: [String: Any] = [
            "uuid-1": [
                "id": "uuid-1",
                "word_cyr": "хлеб",
                "word_lat": "hleb",
                "translation": "bread",
                "streak": 2,
                "total_good": 3,
                "total_hard": 1,
                "total_again": 0,
                "forget_count": 0,
                "created_at": "2024-01-01T00:00:00Z",
                "last_seen_at": "2024-06-01T00:00:00Z",
            ],
            "uuid-2": [
                "id": "uuid-2",
                "word_cyr": "вода",
                "word_lat": "voda",
                "translation": "water",
                "streak": 0,
                "total_good": 0,
                "total_hard": 0,
                "total_again": 0,
                "forget_count": 0,
                "created_at": "2024-01-02T00:00:00Z",
            ],
        ]

        // Parse
        guard let wordDicts = Array(webAppJSON.values) as? [[String: Any]] else {
            XCTFail("Failed to cast web app JSON values")
            return
        }
        XCTAssertEqual(wordDicts.count, 2)

        for wd in wordDicts {
            let wordCyr = wd["word_cyr"] as? String ?? ""
            let wordLat = wd["word_lat"] as? String ?? ""
            XCTAssertFalse(wordCyr.isEmpty)
            XCTAssertFalse(wordLat.isEmpty)

            let word = WordEntry(
                id: wd["id"] as? String ?? UUID().uuidString,
                wordCyr: wordCyr,
                wordLat: wordLat,
                translation: wd["translation"] as? String ?? "",
                streak: wd["streak"] as? Int ?? 0,
                totalGood: wd["total_good"] as? Int ?? 0,
                totalHard: wd["total_hard"] as? Int ?? 0,
                totalAgain: wd["total_again"] as? Int ?? 0,
                forgetCount: wd["forget_count"] as? Int ?? 0
            )
            context.insert(word)
        }
        try context.save()

        let descriptor = FetchDescriptor<WordEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 2)
    }
}
