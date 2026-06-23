import XCTest
@testable import SerbianCards

final class ScoringServiceTests: XCTestCase {

    private func makeConfig() -> AppConfig {
        AppConfig()
    }

    private func makeWord(
        id: String = "test",
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

    private func isoMinutesAgo(_ minutes: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutes * 60))
    }

    // MARK: - Intervals

    func testStreakZeroIsShort() {
        let config = makeConfig()
        let w = makeWord(streak: 0)
        XCTAssertEqual(ScoringService.effectiveIntervalMinutes(word: w, config: config), 10)
    }

    func testStreakGrowsInterval() {
        let config = makeConfig()
        let expected: [(Int, Double)] = [(1, 1440), (2, 4320), (3, 10080), (4, 30240)]
        for (streak, expectedInterval) in expected {
            let w = makeWord(streak: streak)
            XCTAssertEqual(
                ScoringService.effectiveIntervalMinutes(word: w, config: config),
                expectedInterval,
                "streak=\(streak)"
            )
        }
    }

    func testStreakCappedAtMax() {
        let config = makeConfig()
        let w = makeWord(streak: 99)
        XCTAssertEqual(
            ScoringService.effectiveIntervalMinutes(word: w, config: config),
            Double(config.baseIntervalsMinutes.last!)
        )
    }

    func testForgetCountShrinksInterval() {
        let config = makeConfig()
        let noForget = makeWord(streak: 4, forgetCount: 0)
        let once = makeWord(streak: 4, forgetCount: 1)
        let twice = makeWord(streak: 4, forgetCount: 2)
        let ivNoForget = ScoringService.effectiveIntervalMinutes(word: noForget, config: config)
        let ivOnce = ScoringService.effectiveIntervalMinutes(word: once, config: config)
        let ivTwice = ScoringService.effectiveIntervalMinutes(word: twice, config: config)
        XCTAssertLessThan(ivOnce, ivNoForget)
        XCTAssertLessThan(ivTwice, ivOnce)
    }

    func testHardGradeHalves() {
        let config = makeConfig()
        let w = makeWord(streak: 2)
        let goodIv = ScoringService.effectiveIntervalMinutes(word: w, config: config, lastGrade: .good)
        let hardIv = ScoringService.effectiveIntervalMinutes(word: w, config: config, lastGrade: .hard)
        XCTAssertEqual(hardIv, goodIv * config.hardModifier, accuracy: 0.001)
    }

    // MARK: - Error factor

    func testNoAttemptsUsesPrior() {
        let config = makeConfig()
        let w = makeWord()
        let ef = ScoringService.errorFactor(word: w, config: config)
        XCTAssertEqual(ef, 1.0 + config.errorFactorAlpha * config.errorPrior, accuracy: 0.001)
    }

    func testAllCorrectMinimum() {
        let config = makeConfig()
        let w = makeWord(totalGood: 20)
        XCTAssertEqual(ScoringService.errorFactor(word: w, config: config), 1.0, accuracy: 0.001)
    }

    func testAllWrongMax() {
        let config = makeConfig()
        let w = makeWord(totalAgain: 20)
        XCTAssertEqual(
            ScoringService.errorFactor(word: w, config: config),
            1.0 + config.errorFactorAlpha,
            accuracy: 0.001
        )
    }

    func testHardCountsAsHalfError() {
        let config = makeConfig()
        let allGood = makeWord(totalGood: 10)
        let allHard = makeWord(totalHard: 10)
        let allAgain = makeWord(totalAgain: 10)
        let efGood = ScoringService.errorFactor(word: allGood, config: config)
        let efHard = ScoringService.errorFactor(word: allHard, config: config)
        let efAgain = ScoringService.errorFactor(word: allAgain, config: config)
        XCTAssertLessThan(efGood, efHard)
        XCTAssertLessThan(efHard, efAgain)
    }

    func testLowAttemptsBlendedTowardPrior() {
        let config = makeConfig()
        // 1 attempt all wrong: confidence=0.2, smoothed = 0.2 * 1 + 0.8 * 0.3 = 0.44
        let w = makeWord(totalAgain: 1)
        let ef = ScoringService.errorFactor(word: w, config: config)
        XCTAssertEqual(ef, 1.0 + config.errorFactorAlpha * 0.44, accuracy: 0.001)
    }

    // MARK: - Due factor

    func testNeverSeenIsMaxDue() {
        let config = makeConfig()
        let w = makeWord()
        XCTAssertEqual(
            ScoringService.dueFactor(word: w, config: config, now: Date()),
            config.dueFactors.last!,
            accuracy: 0.001
        )
    }

    func testJustSeenIsMinimum() {
        let config = makeConfig()
        let w = makeWord(streak: 2, lastSeenAt: isoMinutesAgo(60))
        XCTAssertEqual(
            ScoringService.dueFactor(word: w, config: config, now: Date()),
            config.dueFactors[0],
            accuracy: 0.001
        )
    }

    func testOverdueIsHigh() {
        let config = makeConfig()
        let w = makeWord(streak: 1, lastSeenAt: isoMinutesAgo(60 * 24 * 10))
        XCTAssertEqual(
            ScoringService.dueFactor(word: w, config: config, now: Date()),
            config.dueFactors.last!,
            accuracy: 0.001
        )
    }

    func testExactlyDue() {
        let config = makeConfig()
        let w = makeWord(streak: 1, lastSeenAt: isoMinutesAgo(1440))
        XCTAssertEqual(
            ScoringService.dueFactor(word: w, config: config, now: Date()),
            config.dueFactors[2],
            accuracy: 0.001
        )
    }

    // MARK: - Recency dampener

    func testJustSeenIsZero() {
        let w = makeWord(lastSeenAt: isoMinutesAgo(0.5))
        XCTAssertEqual(ScoringService.recencyDampener(word: w, now: Date()), 0.0)
    }

    func testAFewMinutesAgoLow() {
        let w = makeWord(lastSeenAt: isoMinutesAgo(5))
        XCTAssertEqual(ScoringService.recencyDampener(word: w, now: Date()), 0.2)
    }

    func testLongAgoFullWeight() {
        let w = makeWord(lastSeenAt: isoMinutesAgo(60))
        XCTAssertEqual(ScoringService.recencyDampener(word: w, now: Date()), 1.0)
    }

    func testNeverSeenFullWeight() {
        let w = makeWord()
        XCTAssertEqual(ScoringService.recencyDampener(word: w, now: Date()), 1.0)
    }

    // MARK: - Apply grade

    func testGoodIncrementsStreakAndTotal() {
        let config = makeConfig()
        let w = makeWord(streak: 1)
        ScoringService.applyGrade(word: w, grade: .good, config: config)
        XCTAssertEqual(w.streak, 2)
        XCTAssertEqual(w.totalGood, 1)
        XCTAssertNotNil(w.lastSeenAt)
        XCTAssertEqual(w.lastCorrectAt, w.lastSeenAt)
        XCTAssertEqual(w.history.last?.grade, "good")
    }

    func testHardIncrementsStreakAndTotalHard() {
        let config = makeConfig()
        let w = makeWord(streak: 1)
        ScoringService.applyGrade(word: w, grade: .hard, config: config)
        XCTAssertEqual(w.streak, 2)
        XCTAssertEqual(w.totalHard, 1)
        XCTAssertEqual(w.lastCorrectAt, w.lastSeenAt)
    }

    func testAgainResetsStreak() {
        let config = makeConfig()
        let w = makeWord(streak: 2)
        ScoringService.applyGrade(word: w, grade: .again, config: config)
        XCTAssertEqual(w.streak, 0)
        XCTAssertEqual(w.totalAgain, 1)
    }

    func testAgainAfterMasteredIncrementsForget() {
        let config = makeConfig()
        let w = makeWord(streak: 4, totalGood: 4)
        XCTAssertTrue(ScoringService.isMastered(word: w, config: config))
        ScoringService.applyGrade(word: w, grade: .again, config: config)
        XCTAssertEqual(w.forgetCount, 1)
        XCTAssertEqual(w.streak, 0)
    }

    func testAgainPreMasteredNoForget() {
        let config = makeConfig()
        let w = makeWord(streak: 2, totalGood: 2)
        ScoringService.applyGrade(word: w, grade: .again, config: config)
        XCTAssertEqual(w.forgetCount, 0)
    }

    func testHistoryRecordsDirection() {
        let config = makeConfig()
        let w = makeWord()
        ScoringService.applyGrade(word: w, grade: .good, config: config, direction: .reverse)
        XCTAssertEqual(w.history.last?.direction, "reverse")
    }

    // MARK: - State classifiers

    func testIsNew() {
        XCTAssertTrue(makeWord().isNew)
        XCTAssertFalse(makeWord(totalGood: 1).isNew)
        XCTAssertFalse(makeWord(totalAgain: 1).isNew)
        XCTAssertFalse(makeWord(totalHard: 1).isNew)
    }

    func testIsMastered() {
        let config = makeConfig()
        XCTAssertFalse(ScoringService.isMastered(word: makeWord(streak: 2), config: config))
        XCTAssertTrue(ScoringService.isMastered(word: makeWord(streak: 3), config: config))
        XCTAssertTrue(ScoringService.isMastered(word: makeWord(streak: 99), config: config))
    }

    func testIsDueNewWordNotDue() {
        let config = makeConfig()
        XCTAssertFalse(ScoringService.isDue(word: makeWord(), config: config, now: Date()))
    }

    func testIsDueOverdue() {
        let config = makeConfig()
        let w = makeWord(streak: 1, totalGood: 1, lastSeenAt: isoMinutesAgo(2 * 1440))
        XCTAssertTrue(ScoringService.isDue(word: w, config: config, now: Date()))
    }

    func testIsDueRecent() {
        let config = makeConfig()
        let w = makeWord(streak: 1, totalGood: 1, lastSeenAt: isoMinutesAgo(60))
        XCTAssertFalse(ScoringService.isDue(word: w, config: config, now: Date()))
    }

    // MARK: - Pick review words

    func testExcludesNewWords() {
        let config = makeConfig()
        let words = [
            makeWord(id: "new1"),
            makeWord(id: "seen1", totalGood: 1, lastSeenAt: isoMinutesAgo(99999)),
        ]
        let picked = ScoringService.pickReviewWords(words: words, config: config, n: 10)
        let ids = Set(picked.map(\.id))
        XCTAssertFalse(ids.contains("new1"))
        XCTAssertTrue(ids.contains("seen1"))
    }

    func testReturnsAtMostN() {
        let config = makeConfig()
        let words = (0..<20).map {
            makeWord(id: "w\($0)", totalGood: 1, lastSeenAt: isoMinutesAgo(99999))
        }
        let picked = ScoringService.pickReviewWords(words: words, config: config, n: 5)
        XCTAssertEqual(picked.count, 5)
        XCTAssertEqual(Set(picked.map(\.id)).count, 5)
    }

    func testEmptyList() {
        let config = makeConfig()
        XCTAssertTrue(ScoringService.pickReviewWords(words: [], config: config, n: 10).isEmpty)
    }

    // MARK: - Random direction

    func testZeroProbabilityAlwaysForward() {
        let config = makeConfig()
        config.reverseProbability = 0.0
        for _ in 0..<50 {
            XCTAssertEqual(ScoringService.randomDirection(config: config), .forward)
        }
    }

    func testOneProbabilityAlwaysReverse() {
        let config = makeConfig()
        config.reverseProbability = 1.0
        for _ in 0..<50 {
            XCTAssertEqual(ScoringService.randomDirection(config: config), .reverse)
        }
    }
}
