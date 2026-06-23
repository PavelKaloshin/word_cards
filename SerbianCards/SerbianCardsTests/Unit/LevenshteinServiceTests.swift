import XCTest
@testable import SerbianCards

final class LevenshteinServiceTests: XCTestCase {

    func testIdenticalStrings() {
        XCTAssertEqual(LevenshteinService.distance("hello", "hello"), 0)
    }

    func testEmptyStrings() {
        XCTAssertEqual(LevenshteinService.distance("", ""), 0)
        XCTAssertEqual(LevenshteinService.distance("abc", ""), 3)
        XCTAssertEqual(LevenshteinService.distance("", "abc"), 3)
    }

    func testSingleCharDifference() {
        XCTAssertEqual(LevenshteinService.distance("cat", "bat"), 1)
        XCTAssertEqual(LevenshteinService.distance("cat", "cats"), 1)
        XCTAssertEqual(LevenshteinService.distance("cat", "at"), 1)
    }

    func testMultipleEdits() {
        XCTAssertEqual(LevenshteinService.distance("kitten", "sitting"), 3)
    }

    func testSerbianWords() {
        // Fuzzy match scenarios for typing mode
        let a = NormalizeService.normalizeForMatch("šahovnica")
        let b = NormalizeService.normalizeForMatch("sahnvica")
        XCTAssertLessThanOrEqual(LevenshteinService.distance(a, b), 3)
    }
}
