import XCTest
@testable import SerbianCards

final class MediaStorageServiceTests: XCTestCase {

    private var testImagePath: String?

    override func setUp() {
        super.setUp()
        MediaStorageService.ensureDirectories()
    }

    override func tearDown() {
        if let path = testImagePath {
            MediaStorageService.deleteFile(path: path)
        }
        super.tearDown()
    }

    func testEnsureDirectoriesCreatesMediaFolders() {
        MediaStorageService.ensureDirectories()
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: MediaStorageService.imagesDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: MediaStorageService.audioDirectory.path))
    }

    func testSaveAndLoadImage() {
        // Create a simple 1x1 red pixel PNG
        let imageData = createTestImageData()
        let wordId = "test-\(UUID().uuidString)"
        guard let path = MediaStorageService.saveImage(data: imageData, wordId: wordId, ext: "png") else {
            XCTFail("Failed to save image")
            return
        }
        testImagePath = path

        // Load it back
        let loaded = MediaStorageService.loadImage(path: path)
        XCTAssertNotNil(loaded, "Should be able to load saved image")
    }

    func testLoadImageReturnsNilForEmptyPath() {
        XCTAssertNil(MediaStorageService.loadImage(path: ""))
    }

    func testLoadImageReturnsNilForMissingFile() {
        XCTAssertNil(MediaStorageService.loadImage(path: "/nonexistent/path/image.png"))
    }

    func testDeleteFile() {
        let imageData = createTestImageData()
        let wordId = "test-delete-\(UUID().uuidString)"
        guard let path = MediaStorageService.saveImage(data: imageData, wordId: wordId, ext: "png") else {
            XCTFail("Failed to save image")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        MediaStorageService.deleteFile(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testMD5Hash() {
        let data = Data("test data for hashing".utf8)
        let hash = data.md5String
        XCTAssertEqual(hash.count, 32, "MD5 hash should be 32 hex characters")
        // Same data should produce same hash
        let hash2 = data.md5String
        XCTAssertEqual(hash, hash2)
    }

    private func createTestImageData() -> Data {
        // Create minimal valid PNG data (1x1 red pixel)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
