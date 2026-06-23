import XCTest
@testable import SerbianCards

final class SessionServiceTests: XCTestCase {

    private func makeConfig() -> AppConfig {
        let cfg = AppConfig()
        cfg.reverseProbability = 0.0 // deterministic for tests
        return cfg
    }

    private func makeWord(
        id: String,
        streak: Int = 0,
        totalGood: Int = 0,
        totalAgain: Int = 0,
        totalHard: Int = 0,
        forgetCount: Int = 0,
        lastSeenAt: String? = nil
    ) -> WordEntry {
        WordEntry(
            id: id,
            lastSeenAt: lastSeenAt,
            streak: streak,
            totalGood: totalGood,
            totalHard: totalHard,
            totalAgain: totalAgain,
            forgetCount: forgetCount
        )
    }

    private func makeLookup(_ words: [WordEntry]) -> (String) -> WordEntry? {
        let dict = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        return { dict[$0] }
    }

    // MARK: - Learn session

    func testStartsWithOnlyNewWords() {
        let config = makeConfig()
        let words = [
            makeWord(id: "new1"),
            makeWord(id: "new2"),
            makeWord(id: "seen", totalGood: 2, lastSeenAt: "2020-01-01T00:00:00Z"),
        ]
        let session = SessionService.startLearnSession(words: words, config: config)
        var allIds = session.queue
        if let current = session.current {
            allIds.append(current.wordId)
        }
        XCTAssertTrue(Set(allIds).isSubset(of: ["new1", "new2"]))
        XCTAssertFalse(allIds.contains("seen"))
    }

    func testFinishesWhenAllMastered() {
        let config = makeConfig()
        config.masteredThreshold = 3
        let word = makeWord(id: "w1")
        let lookup = makeLookup([word])
        let session = SessionService.startLearnSession(words: [word], config: config)

        for _ in 0..<3 {
            SessionService.answer(
                session: session, grade: .good, config: config,
                wordLookup: lookup, saveWord: { _ in }
            )
        }
        XCTAssertNil(session.current)
        XCTAssertTrue(session.newMasteredIds.contains("w1"))
    }

    func testAgainReQueuesNearFront() {
        let config = makeConfig()
        let words = (0..<5).map { makeWord(id: "w\($0)") }
        let lookup = makeLookup(words)
        let session = SessionService.startLearnSession(words: words, config: config)

        let first = session.current!.wordId
        SessionService.answer(
            session: session, grade: .again, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )

        var idsLeft = session.queue
        if let current = session.current {
            idsLeft.insert(current.wordId, at: 0)
        }
        XCTAssertTrue(idsLeft.contains(first))
        if let idx = idsLeft.firstIndex(of: first) {
            XCTAssertLessThanOrEqual(idx, 3)
        }
    }

    func testGoodReQueuesToEnd() {
        let config = makeConfig()
        let words = (0..<3).map { makeWord(id: "w\($0)") }
        let lookup = makeLookup(words)
        let session = SessionService.startLearnSession(words: words, config: config)

        let first = session.current!.wordId
        SessionService.answer(
            session: session, grade: .good, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )

        if !session.queue.isEmpty {
            XCTAssertEqual(session.queue.last, first)
        }
    }

    func testMaxNewPerSessionCaps() {
        let config = makeConfig()
        config.maxNewPerSession = 2
        let words = (0..<10).map { makeWord(id: "w\($0)") }
        let session = SessionService.startLearnSession(words: words, config: config)

        var allIds = session.queue
        if let current = session.current {
            allIds.append(current.wordId)
        }
        XCTAssertEqual(allIds.count, 2)
    }

    func testIncrementsTotalGood() {
        let config = makeConfig()
        let word = makeWord(id: "w1")
        let lookup = makeLookup([word])
        let session = SessionService.startLearnSession(words: [word], config: config)

        SessionService.answer(
            session: session, grade: .good, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )
        XCTAssertEqual(word.totalGood, 1)
    }

    // MARK: - Review session

    func testOnlySeenWords() {
        let config = makeConfig()
        let words = [
            makeWord(id: "new1"),
            makeWord(id: "seen1", totalGood: 1, lastSeenAt: "2020-01-01T00:00:00Z"),
            makeWord(id: "seen2", totalGood: 1, lastSeenAt: "2020-01-01T00:00:00Z"),
        ]
        let session = SessionService.startReviewSession(words: words, config: config, size: 10)
        var allIds = session.queue
        if let current = session.current {
            allIds.append(current.wordId)
        }
        XCTAssertFalse(allIds.contains("new1"))
    }

    func testSizeCapsQueue() {
        let config = makeConfig()
        let words = (0..<50).map {
            makeWord(id: "w\($0)", totalGood: 1, lastSeenAt: "2020-01-01T00:00:00Z")
        }
        let session = SessionService.startReviewSession(words: words, config: config, size: 5)
        var allIds = session.queue
        if let current = session.current {
            allIds.append(current.wordId)
        }
        XCTAssertEqual(allIds.count, 5)
    }

    func testFinishesAfterNAnswers() {
        let config = makeConfig()
        let words = (0..<5).map {
            makeWord(id: "w\($0)", totalGood: 1, lastSeenAt: "2020-01-01T00:00:00Z")
        }
        let lookup = makeLookup(words)
        let session = SessionService.startReviewSession(words: words, config: config, size: 5)

        var answersGiven = 0
        while session.current != nil && answersGiven < 100 {
            SessionService.answer(
                session: session, grade: .good, config: config,
                wordLookup: lookup, saveWord: { _ in }
            )
            answersGiven += 1
        }
        XCTAssertNil(session.current)
        XCTAssertEqual(answersGiven, 5)
    }

    // MARK: - HUD

    func testReviewProgressCountsDoneVsRemaining() {
        let config = makeConfig()
        let words = (0..<3).map {
            makeWord(id: "w\($0)", totalGood: 1, lastSeenAt: "2020-01-01T00:00:00Z")
        }
        let lookup = makeLookup(words)
        let session = SessionService.startReviewSession(words: words, config: config, size: 3)

        var h = SessionService.hud(session: session)
        XCTAssertEqual(h.total, 3)
        XCTAssertEqual(h.position, 0)

        SessionService.answer(
            session: session, grade: .good, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )
        h = SessionService.hud(session: session)
        XCTAssertEqual(h.position, 1)
    }

    func testLearnProgressCountsMastered() {
        let config = makeConfig()
        config.masteredThreshold = 1
        let word = makeWord(id: "w1")
        let lookup = makeLookup([word])
        let session = SessionService.startLearnSession(words: [word], config: config)

        var h = SessionService.hud(session: session)
        XCTAssertEqual(h.total, 1)
        XCTAssertEqual(h.position, 0)

        SessionService.answer(
            session: session, grade: .good, config: config,
            wordLookup: lookup, saveWord: { _ in }
        )
        h = SessionService.hud(session: session)
        XCTAssertEqual(h.position, 1)
    }
}
