import Foundation

/// Port of backend/scoring.py — all SRS math.
enum ScoringService {

    // MARK: - Time helpers

    static func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    // MARK: - Interval computation

    static func baseIntervalMinutes(streak: Int, baseIntervals: [Int]) -> Double {
        let idx = max(0, min(streak, baseIntervals.count - 1))
        return Double(baseIntervals[idx])
    }

    /// Interval until next show, given current state and the last grade given.
    static func effectiveIntervalMinutes(
        word: WordEntry,
        config: AppConfig,
        lastGrade: Grade? = nil
    ) -> Double {
        let base = baseIntervalMinutes(streak: word.streak, baseIntervals: config.baseIntervalsMinutes)
        let decay = 1.0 / (1.0 + Double(word.forgetCount) * config.forgetDecayAlpha)
        let hardMod = lastGrade == .hard ? config.hardModifier : 1.0
        return base * decay * hardMod
    }

    // MARK: - Weight factors

    static func errorFactor(word: WordEntry, config: AppConfig) -> Double {
        let g = word.totalGood
        let a = word.totalAgain
        let h = word.totalHard
        let attempts = g + a + h
        let errorRate = Double(a) + 0.5 * Double(h)
        let normalizedError = errorRate / Double(max(1, attempts))
        let confidence = min(1.0, Double(attempts) / 5.0)
        let smoothed = confidence * normalizedError + (1.0 - confidence) * config.errorPrior
        return 1.0 + config.errorFactorAlpha * smoothed
    }

    static func dueFactor(word: WordEntry, config: AppConfig, now: Date) -> Double {
        guard let lastSeen = parseISO(word.lastSeenAt) else {
            return config.dueFactors.last ?? 5.0
        }
        let interval = effectiveIntervalMinutes(word: word, config: config)
        guard interval > 0 else {
            return config.dueFactors.last ?? 5.0
        }
        let minutesSince = now.timeIntervalSince(lastSeen) / 60.0
        let ratio = minutesSince / interval

        for (i, threshold) in config.dueThresholds.enumerated() {
            if ratio < threshold {
                return config.dueFactors[i]
            }
        }
        return config.dueFactors.last ?? 5.0
    }

    static func recencyDampener(word: WordEntry, now: Date) -> Double {
        guard let lastSeen = parseISO(word.lastSeenAt) else {
            return 1.0
        }
        let minutesSince = now.timeIntervalSince(lastSeen) / 60.0
        if minutesSince < 2 {
            return 0.0
        }
        if minutesSince < 10 {
            return 0.2
        }
        return 1.0
    }

    static func reviewWeight(word: WordEntry, config: AppConfig, now: Date) -> Double {
        return errorFactor(word: word, config: config)
            * dueFactor(word: word, config: config, now: now)
            * recencyDampener(word: word, now: now)
    }

    // MARK: - State classifiers

    static func isMastered(word: WordEntry, config: AppConfig) -> Bool {
        word.streak >= config.masteredThreshold
    }

    static func isDue(word: WordEntry, config: AppConfig, now: Date) -> Bool {
        if word.isNew { return false }
        guard let lastSeen = parseISO(word.lastSeenAt) else { return true }
        let interval = effectiveIntervalMinutes(word: word, config: config)
        let minutesSince = now.timeIntervalSince(lastSeen) / 60.0
        return minutesSince >= interval
    }

    // MARK: - Word selection

    /// Weighted random sample without replacement.
    static func pickReviewWords(words: [WordEntry], config: AppConfig, n: Int) -> [WordEntry] {
        let now = Date()
        let candidates = words.filter { !$0.isNew }
        if candidates.isEmpty { return [] }

        var weights = candidates.map { reviewWeight(word: $0, config: config, now: now) }
        let totalWeight = weights.reduce(0, +)
        if totalWeight == 0 {
            return Array(candidates.shuffled().prefix(n))
        }

        var picked: [WordEntry] = []
        var pool = Array(zip(candidates, weights))

        for _ in 0..<min(n, pool.count) {
            let total = pool.map(\.1).reduce(0, +)
            if total == 0 { break }
            let r = Double.random(in: 0..<total)
            var acc = 0.0
            for i in pool.indices {
                acc += pool[i].1
                if acc >= r {
                    picked.append(pool[i].0)
                    pool.remove(at: i)
                    break
                }
            }
        }
        return picked
    }

    // MARK: - Grade application

    /// Mutates word in-place. Caller is responsible for persisting.
    static func applyGrade(
        word: WordEntry,
        grade: Grade,
        config: AppConfig,
        direction: Direction = .forward
    ) {
        let wasMastered = isMastered(word: word, config: config)
        let timestamp = nowISO()
        word.lastSeenAt = timestamp

        switch grade {
        case .good:
            word.streak += 1
            word.totalGood += 1
            word.lastCorrectAt = timestamp
        case .hard:
            word.streak += 1
            word.totalHard += 1
            word.lastCorrectAt = timestamp
        case .again:
            if wasMastered {
                word.forgetCount += 1
            }
            word.streak = 0
            word.totalAgain += 1
        }

        word.history.append(AnswerRecord(
            ts: timestamp,
            grade: grade.rawValue,
            direction: direction.rawValue
        ))
    }

    // MARK: - Direction

    static func randomDirection(config: AppConfig) -> Direction {
        Double.random(in: 0..<1) < config.reverseProbability ? .reverse : .forward
    }
}
