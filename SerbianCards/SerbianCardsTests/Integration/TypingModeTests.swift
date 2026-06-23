import XCTest
import SwiftData
@testable import SerbianCards

final class TypingModeTests: XCTestCase {

    func testExactMatchIsGood() {
        let config = AppConfig()
        let normTyped = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: config.typingRelaxedDiacritics)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: config.typingRelaxedDiacritics)
        let distance = LevenshteinService.distance(normTyped, normTarget)
        XCTAssertEqual(distance, 0)
    }

    func testRelaxedDiacriticsMatchesExact() {
        let config = AppConfig()
        XCTAssertTrue(config.typingRelaxedDiacritics) // default is true

        let normTyped = NormalizeService.normalizeForMatch("kuca", relaxedDiacritics: true)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: true)
        let distance = LevenshteinService.distance(normTyped, normTarget)
        XCTAssertEqual(distance, 0, "With relaxed diacritics, kuca should match kuća")
    }

    func testStrictDiacriticsDoesNotMatch() {
        let normTyped = NormalizeService.normalizeForMatch("kuca", relaxedDiacritics: false)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: false)
        let distance = LevenshteinService.distance(normTyped, normTarget)
        XCTAssertGreaterThan(distance, 0, "With strict diacritics, kuca should not match kuća")
    }

    func testCloseTypoIsHard() {
        let config = AppConfig()
        let normTyped = NormalizeService.normalizeForMatch("kuc", relaxedDiacritics: config.typingRelaxedDiacritics)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: config.typingRelaxedDiacritics)
        let distance = LevenshteinService.distance(normTyped, normTarget)

        let threshold = config.typingHardLevenshteinThreshold
        // "kuc" vs "kuca" -> distance 1 -> should be hard
        XCTAssertGreaterThan(distance, 0)
        XCTAssertLessThanOrEqual(distance, threshold)
    }

    func testFarTypoIsAgain() {
        let config = AppConfig()
        let normTyped = NormalizeService.normalizeForMatch("xyz", relaxedDiacritics: config.typingRelaxedDiacritics)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: config.typingRelaxedDiacritics)
        let distance = LevenshteinService.distance(normTyped, normTarget)

        let threshold = config.typingHardLevenshteinThreshold
        XCTAssertGreaterThan(distance, threshold, "Completely wrong input should exceed threshold")
    }

    func testCyrillicInputMatchesLatinTarget() {
        let config = AppConfig()
        let normTyped = NormalizeService.normalizeForMatch("кућа", relaxedDiacritics: config.typingRelaxedDiacritics)
        let normTarget = NormalizeService.normalizeForMatch("kuća", relaxedDiacritics: config.typingRelaxedDiacritics)
        let distance = LevenshteinService.distance(normTyped, normTarget)
        XCTAssertEqual(distance, 0, "Cyrillic input should match Latin target after normalization")
    }

    func testGradeAssignment() {
        let config = AppConfig()
        let threshold = config.typingHardLevenshteinThreshold

        // Test grade logic
        XCTAssertEqual(gradeForDistance(0, threshold: threshold), .good)
        XCTAssertEqual(gradeForDistance(1, threshold: threshold), .hard)
        XCTAssertEqual(gradeForDistance(2, threshold: threshold), .hard) // threshold default is 2
        XCTAssertEqual(gradeForDistance(3, threshold: threshold), .again)
        XCTAssertEqual(gradeForDistance(10, threshold: threshold), .again)
    }

    private func gradeForDistance(_ distance: Int, threshold: Int) -> Grade {
        if distance == 0 { return .good }
        if distance <= threshold { return .hard }
        return .again
    }
}
