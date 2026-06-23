import UIKit

/// Manages media files (images, audio) in the app's Documents/media/ directory.
enum MediaStorageService {

    static var mediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("media", isDirectory: true)
    }

    static var imagesDirectory: URL {
        mediaDirectory.appendingPathComponent("images", isDirectory: true)
    }

    static var audioDirectory: URL {
        mediaDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    /// Ensure media directories exist.
    static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [imagesDirectory, audioDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    /// Save image data to the images directory. Returns the relative file path.
    static func saveImage(data: Data, wordId: String, ext: String = "jpg") -> String? {
        ensureDirectories()
        let fileName = "\(wordId).\(ext)"
        let url = imagesDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    /// Load a UIImage from a file path.
    static func loadImage(path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = imagesDirectory.appendingPathComponent(path)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Delete a file at the given path.
    static func deleteFile(path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Get the full URL for a relative media path.
    static func fullURL(for relativePath: String) -> URL {
        mediaDirectory.appendingPathComponent(relativePath)
    }

    /// List all files in a directory.
    static func listFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    /// Compute MD5 hash of a file.
    static func md5Hash(of path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return data.md5String
    }
}

import CommonCrypto

extension Data {
    var md5String: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = withUnsafeBytes { CC_MD5($0.baseAddress, CC_LONG(count), &digest) }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
