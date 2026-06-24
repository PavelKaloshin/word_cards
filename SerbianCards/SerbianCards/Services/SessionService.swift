import Foundation

/// Port of backend/session.py — session state machine for learn and review modes.
enum SessionService {

    // MARK: - Session creation

    /// Start a learn session with only new (unseen) words.
    static func startLearnSession(
        words: [WordEntry],
        config: AppConfig,
        maxSize: Int? = nil
    ) -> ActiveSession {
        var newWords = words.filter { $0.isNew }
        newWords.shuffle()
        let cap = maxSize ?? config.maxNewPerSession
        if let cap {
            newWords = Array(newWords.prefix(cap))
        }
        let wordIds = newWords.map(\.id)
        let session = ActiveSession(
            mode: .learn,
            queue: Array(wordIds)
        )
        session.learnInitialTotal = newWords.count
        session.learnWordIds = Array(wordIds)
        advance(session, direction: .forward)
        return session
    }

    /// Start a review session with weighted random sample of previously seen words.
    static func startReviewSession(
        words: [WordEntry],
        config: AppConfig,
        size: Int? = nil
    ) -> ActiveSession {
        let n = size ?? config.reviewSessionSize
        let picks = ScoringService.pickReviewWords(words: words, config: config, n: n)
        let session = ActiveSession(
            mode: .review,
            queue: picks.map(\.id)
        )
        advance(session, direction: ScoringService.randomDirection(config: config))
        return session
    }

    // MARK: - Session flow

    /// Pop next word from queue into `current`, or set current=nil if empty.
    private static func advance(_ session: ActiveSession, direction: Direction) {
        guard !session.queue.isEmpty else {
            session.current = nil
            return
        }
        let nextId = session.queue.removeFirst()
        session.current = CurrentCard(wordId: nextId, direction: direction)
    }

    /// Apply grade to current word and advance to next.
    /// The `wordLookup` closure fetches a WordEntry by ID, and `saveWord` persists changes.
    @discardableResult
    static func answer(
        session: ActiveSession,
        grade: Grade,
        config: AppConfig,
        wordLookup: (String) -> WordEntry?,
        saveWord: (WordEntry) -> Void
    ) -> CurrentCard? {
        guard let currentCard = session.current else { return nil }

        let wordId = currentCard.wordId
        let direction = currentCard.direction

        guard let word = wordLookup(wordId) else {
            let nextDirection: Direction = session.mode == .review
                ? ScoringService.randomDirection(config: config)
                : .forward
            advance(session, direction: nextDirection)
            return session.current
        }

        let wasMastered = ScoringService.isMastered(word: word, config: config)
        ScoringService.applyGrade(word: word, grade: grade, config: config, direction: direction)
        saveWord(word)

        // HUD counters
        switch grade {
        case .good: session.goodCount += 1
        case .hard: session.hardCount += 1
        case .again: session.againCount += 1
        }

        let threshold = config.masteredThreshold

        // Monotonic correct-count for learn-mode progress bar
        if session.mode == .learn,
           grade == .good || grade == .hard,
           session.learnWordIds.contains(wordId) {
            let cur = session.learnCorrectCount[wordId] ?? 0
            session.learnCorrectCount[wordId] = min(cur + 1, threshold)
        }

        session.reviewResults.append(SessionResult(
            wordId: wordId,
            grade: grade.rawValue,
            direction: direction.rawValue,
            ts: ScoringService.nowISO()
        ))

        if session.mode == .learn {
            // Learn-mode completion is count-based (monotonic) — keeps HUD,
            // progress bar, and queue exit consistent regardless of streak resets.
            let completed = session.learnWordIds.contains(wordId)
                && (session.learnCorrectCount[wordId] ?? 0) >= threshold
            if completed {
                session.newMasteredIds.insert(wordId)
            } else {
                reinsertLearn(session, wordId: wordId, grade: grade)
            }
            advance(session, direction: .forward)
        } else {
            // Review mode keeps streak-based mastery for stats / end-of-session summary.
            let isMasteredNow = ScoringService.isMastered(word: word, config: config)
            if isMasteredNow && !wasMastered {
                session.newMasteredIds.insert(wordId)
            }
            advance(session, direction: ScoringService.randomDirection(config: config))
        }

        return session.current
    }

    /// Leitner-style reinsertion based on grade.
    private static func reinsertLearn(_ session: ActiveSession, wordId: String, grade: Grade) {
        let q = session.queue
        let pos: Int
        switch grade {
        case .again:
            pos = min(2, q.count)
        case .hard:
            pos = max(1, q.count / 2)
        case .good:
            pos = q.count
        }
        session.queue.insert(wordId, at: pos)
    }

    /// End the session.
    static func end(_ session: ActiveSession) {
        session.endedAt = ScoringService.nowISO()
        session.current = nil
    }

    // MARK: - Summary

    /// Build session summary for persisting to SessionRecord.
    static func toSummary(
        session: ActiveSession,
        wordLookup: (String) -> WordEntry?
    ) -> (SessionSummary, [SessionResult]) {
        let shown = session.goodCount + session.hardCount + session.againCount
        let accuracy = shown > 0
            ? Double(session.goodCount + session.hardCount) / Double(shown)
            : 0.0

        // Find worst words (most "again" in this session)
        var againPerWord: [String: Int] = [:]
        for r in session.reviewResults {
            if r.grade == Grade.again.rawValue {
                againPerWord[r.wordId, default: 0] += 1
            }
        }
        let hardest = againPerWord.sorted { $0.value > $1.value }.prefix(5)
        let hardestWords: [HardestWord] = hardest.compactMap { (wordId, count) in
            guard let w = wordLookup(wordId) else { return nil }
            return HardestWord(id: wordId, wordCyr: w.wordCyr, wordLat: w.wordLat, againCount: count)
        }

        let summary = SessionSummary(
            shown: shown,
            good: session.goodCount,
            hard: session.hardCount,
            again: session.againCount,
            accuracy: (accuracy * 1000).rounded() / 1000,
            newMastered: session.newMasteredIds.count,
            hardest: hardestWords
        )

        return (summary, session.reviewResults)
    }

    // MARK: - HUD

    /// Compute live HUD data for the session.
    static func hud(
        session: ActiveSession,
        wordLookup: ((String) -> WordEntry?)? = nil,
        config: AppConfig? = nil
    ) -> SessionHUD {
        let position: Int
        let total: Int

        if session.mode == .learn {
            position = session.newMasteredIds.count
            total = session.learnInitialTotal
        } else {
            let done = session.goodCount + session.hardCount + session.againCount
            let remaining = session.queue.count + (session.current != nil ? 1 : 0)
            total = done + remaining
            position = done
        }

        let shown = session.goodCount + session.hardCount + session.againCount
        let accuracy = shown > 0
            ? Double(session.goodCount + session.hardCount) / Double(shown)
            : 0.0

        return SessionHUD(
            good: session.goodCount + session.hardCount,
            hard: session.hardCount,
            again: session.againCount,
            accuracy: (accuracy * 1000).rounded() / 1000,
            position: position,
            total: total,
            mode: session.mode
        )
    }

    /// Compute learn-mode progress strip data.
    static func computeLearnProgress(
        session: ActiveSession,
        config: AppConfig,
        wordLookup: (String) -> WordEntry?
    ) -> LearnProgress {
        let threshold = config.masteredThreshold
        let wordIds = session.learnWordIds.isEmpty ? session.queue : session.learnWordIds
        var items: [LearnProgressItem] = []
        var totalCorrect = 0

        for wid in wordIds {
            guard let w = wordLookup(wid) else { continue }
            let correct = min(session.learnCorrectCount[wid] ?? 0, threshold)
            totalCorrect += correct
            items.append(LearnProgressItem(
                id: wid,
                wordCyr: w.wordCyr,
                wordLat: w.wordLat,
                translation: w.translation,
                imagePath: w.imagePath,
                correctCount: correct,
                streak: w.streak,
                completed: correct >= threshold
            ))
        }

        let completed = items.filter(\.completed).count
        return LearnProgress(
            threshold: threshold,
            totalCorrect: totalCorrect,
            maxCorrect: threshold * items.count,
            completedWords: completed,
            remainingWords: items.count - completed,
            totalWords: items.count,
            words: items
        )
    }
}
