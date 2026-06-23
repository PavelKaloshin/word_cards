import XCTest
@testable import SerbianCards

final class NormalizeServiceTests: XCTestCase {

    // MARK: - toBoth

    func testCyrillicInput() {
        let (cyr, lat) = NormalizeService.toBoth("хлеб")
        XCTAssertEqual(cyr, "хлеб")
        XCTAssertEqual(lat, "hleb")
    }

    func testLatinInput() {
        let (cyr, lat) = NormalizeService.toBoth("hleb")
        XCTAssertEqual(cyr, "хлеб")
        XCTAssertEqual(lat, "hleb")
    }

    func testDiacriticLatin() {
        let (cyr, lat) = NormalizeService.toBoth("Ćao")
        XCTAssertEqual(cyr, "Ћао")
        XCTAssertEqual(lat, "Ćao")
    }

    func testDiacriticCyrillic() {
        let (cyr, lat) = NormalizeService.toBoth("ћао")
        XCTAssertEqual(cyr, "ћао")
        XCTAssertEqual(lat, "ćao")
    }

    func testDigraphsLatinToCyrillic() {
        let (cyr, lat) = NormalizeService.toBoth("ljubav")
        XCTAssertEqual(cyr, "љубав")
        XCTAssertEqual(lat, "ljubav")
    }

    func testDzDigraph() {
        let (cyr, _) = NormalizeService.toBoth("džak")
        XCTAssertEqual(cyr, "џак")
    }

    func testCapitalDigraph() {
        let (cyr, lat) = NormalizeService.toBoth("Njuška")
        XCTAssertTrue(cyr.hasPrefix("Њ"))
        XCTAssertEqual(lat, "Njuška")
    }

    func testDjordjeDjSpecial() {
        let (cyr, lat) = NormalizeService.toBoth("Đorđe")
        XCTAssertEqual(cyr, "Ђорђе")
        XCTAssertEqual(lat, "Đorđe")
    }

    func testEmpty() {
        let (cyr, lat) = NormalizeService.toBoth("")
        XCTAssertEqual(cyr, "")
        XCTAssertEqual(lat, "")
    }

    func testWhitespaceStripped() {
        let (cyr, lat) = NormalizeService.toBoth("  hleb  ")
        XCTAssertEqual(cyr, "хлеб")
        XCTAssertEqual(lat, "hleb")
    }

    // MARK: - normalizeForMatch

    func testExactMatch() {
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("hleb"),
            NormalizeService.normalizeForMatch("hleb")
        )
    }

    func testCyrillicToLatin() {
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("хлеб"),
            NormalizeService.normalizeForMatch("hleb")
        )
    }

    func testDiacriticRelaxed() {
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("šahovnica"),
            NormalizeService.normalizeForMatch("sahovnica")
        )
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("ćao"),
            NormalizeService.normalizeForMatch("cao")
        )
    }

    func testDiacriticStrict() {
        let a = NormalizeService.normalizeForMatch("šahovnica", relaxedDiacritics: false)
        let b = NormalizeService.normalizeForMatch("sahovnica", relaxedDiacritics: false)
        XCTAssertNotEqual(a, b)
    }

    func testDjSpecial() {
        // Đak -> djak in relaxed mode
        XCTAssertEqual(NormalizeService.normalizeForMatch("Đak"), "djak")
        // In strict mode it preserves the đ
        XCTAssertEqual(NormalizeService.normalizeForMatch("Đak", relaxedDiacritics: false), "đak")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("HLEB"),
            NormalizeService.normalizeForMatch("hleb")
        )
    }

    func testCyrillicWithDiacritic() {
        // ћ in Cyrillic is the same sound as ć in Latin -> both should normalize to "c"
        XCTAssertEqual(
            NormalizeService.normalizeForMatch("ћао"),
            NormalizeService.normalizeForMatch("ćao")
        )
        XCTAssertEqual(NormalizeService.normalizeForMatch("ћао"), "cao")
    }

    // MARK: - isCyrillic

    func testLatinString() {
        XCTAssertFalse(NormalizeService.isCyrillic("hleb"))
    }

    func testCyrillicString() {
        XCTAssertTrue(NormalizeService.isCyrillic("хлеб"))
    }

    func testMixedPicksCyrillic() {
        XCTAssertTrue(NormalizeService.isCyrillic("hleb и xлеб"))
    }
}
