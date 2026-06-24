import XCTest
@testable import SerbianCards

final class KeychainServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any leftover test key
        KeychainService.deleteAPIKey()
    }

    override func tearDown() {
        KeychainService.deleteAPIKey()
        super.tearDown()
    }

    func testSaveAndLoadAPIKey() {
        let key = "sk-test-key-1234567890"
        XCTAssertTrue(KeychainService.saveAPIKey(key))
        XCTAssertEqual(KeychainService.loadAPIKey(), key)
    }

    func testHasAPIKey() {
        XCTAssertFalse(KeychainService.hasAPIKey())
        KeychainService.saveAPIKey("sk-test")
        XCTAssertTrue(KeychainService.hasAPIKey())
    }

    func testDeleteAPIKey() {
        KeychainService.saveAPIKey("sk-test")
        XCTAssertTrue(KeychainService.hasAPIKey())
        XCTAssertTrue(KeychainService.deleteAPIKey())
        XCTAssertFalse(KeychainService.hasAPIKey())
        XCTAssertNil(KeychainService.loadAPIKey())
    }

    func testOverwriteAPIKey() {
        KeychainService.saveAPIKey("sk-first")
        KeychainService.saveAPIKey("sk-second")
        XCTAssertEqual(KeychainService.loadAPIKey(), "sk-second")
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(KeychainService.loadAPIKey())
    }
}
