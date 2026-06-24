import XCTest
import SwiftData
@testable import SerbianCards

final class SessionFlowTests: XCTestCase {

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

    private func createWords(count: Int) -> [WordEntry] {
        (0..<count).map { i in
            let word = WordEntry(
                id: "w\(i)",
                wordCyr: "слово\(i)",
                wordLat: "slovo\(i)",
                translation: "word\(i)"
            )
            context.insert(word)
            return word
        }
    }

    private func createSeenWords(count: Int) -> [WordEntry] {
        (0..<count).map { i in
            let word = WordEntry(
                id: "sw\(i)",
                wordCyr: "реч\(i)",
                wordLat: "rec\(i)",
                translation: "word\(i)",
                lastSeenAt: "2020-01-01T00:00:00Z",
                totalGood: 1
            )
            context.insert(word)
            return word
        }
    }

    func testLearnSessionFlow() throws {
        let config = AppConfig()
        config.masteredThreshold = 2
        config.reverseProbability = 0.0
        context.insert(config)
        try context.save()

        let words = createWords(count: 3)
        let session = SessionService.startLearnSession(words: words, config: config)
        XCTAssertNotNil(session.current)
        XCTAssertEqual(session.mode, .learn)

        let lookup: (String) -> WordEntry? = { id in words.first { $0.id == id } }

        // Grade all words good once
        var answeredCount = 0
        while session.current != nil && answeredCount < 50 {
            SessionService.answer(
                session: session, grade: .good, config: config,
                wordLookup: lookup, saveWord: { _ in }
            )
            answeredCount += 1
        }

        // With threshold=2, each word needs 2 goods. Total answers should be 6 (3 words * 2)
        XCTAssertNil(session.current)
        XCTAssertEqual(session.newMasteredIds.count, 3)

        // End and verify summary
        SessionService.end(session)
        let (summary, results) = SessionService.toSummary(session: session, wordLookup: lookup)
        XCTAssertEqual(summary.shown, answeredCount)
        XCTAssertEqual(summary.newMastered, 3)
        XCTAssertGreaterThan(summary.accuracy, 0)

        // Save session record
        let record = SessionRecord(
            id: session.id,
            mode: session.mode.rawValue,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            results: results,
            summary: summary
        )
        context.insert(record)
        try context.save()

        let sessionDescriptor = FetchDescriptor<SessionRecord>()
        let savedSessions = try context.fetch(sessionDescriptor)
        XCTAssertEqual(savedSessions.count, 1)
        XCTAssertEqual(savedSessions[0].summary.newMastered, 3)
    }

    func testReviewSessionFlow() throws {
        let config = AppConfig()
        config.reverseProbability = 0.0
        context.insert(config)
        try context.save()

        let words = createSeenWords(count: 10)
        let session = SessionService.startReviewSession(words: words, config: config, size: 5)
        XCTAssertNotNil(session.current)
        XCTAssertEqual(session.mode, .review)

        let lookup: (String) -> WordEntry? = { id in words.first { $0.id == id } }

        // Answer all
        var answeredCount = 0
        while session.current != nil && answeredCount < 100 {
            let grade: Grade = answeredCount % 3 == 0 ? .again : (answeredCount % 3 == 1 ? .hard : .good)
            SessionService.answer(
                session: session, grade: grade, config: config,
                wordLookup: lookup, saveWord: { _ in }
            )
            answeredCount += 1
        }

        XCTAssertEqual(answeredCount, 5)
        XCTAssertNil(session.current)

        // Verify HUD after completion
        let hud = SessionService.hud(session: session)
        XCTAssertEqual(hud.position, 5)
    }

    func testLeitnerRequeuePositions() throws {
        let config = AppConfig()
        config.masteredThreshold = 10 // high threshold so nothing gets mastered
        config.reverseProbability = 0.0
        context.insert(config)
        try context.save()

        let words = createWords(count: 5)
        let session = SessionService.startLearnSession(words: words, config: config)
        let lookup: (String) -> WordEntry? = { id in words.first { $0.id == id } }

        // Grade "again" — should reinsert near front (position 2)
        let firstWord = session.current!.wordId
        SessionService.answer(
            session: session, grade: .again, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )

        var remaining = session.queue
        if let current = session.current {
            remaining.insert(current.wordId, at: 0)
        }
        XCTAssertTrue(remaining.contains(firstWord))
        if let idx = remaining.firstIndex(of: firstWord) {
            XCTAssertLessThanOrEqual(idx, 3, "Again should reinsert near front")
        }
    }
}
