import Foundation

/// Port of backend/images.py — image search via free public APIs (no API key needed).
actor ImageSearchService {
    static let shared = ImageSearchService()
    private init() {}

    private let userAgent = "WordCards/1.0 (iOS; Serbian flashcard app)"
    private let timeout: TimeInterval = 15.0
    private let validExtensions: Set<String> = [".jpg", ".jpeg", ".png", ".gif", ".webp"]

    // MARK: - Public API

    /// Search for an image and save it. Returns saved file path or nil.
    func searchAndSave(
        wordSerbian: String,
        translation: String,
        wordId: String,
        config: AppConfig,
        skipHashes: Set<String> = [],
        evalEnabled: Bool = true
    ) async -> String? {
        let candidates = iterCandidateURLs(
            wordSerbian: wordSerbian,
            translation: translation,
            lang: config.imageSearchLang
        )

        let maxToCheck = config.imageEvalMaxCandidates + skipHashes.count * 2
        for url in candidates.prefix(maxToCheck) {
            guard let (data, ext) = await download(url: url) else { continue }

            // Hash check
            let digest = data.md5String
            if skipHashes.contains(digest) { continue }

            // Save
            guard let path = MediaStorageService.saveImage(
                data: data,
                wordId: wordId,
                ext: ext
            ) else { continue }

            // Evaluate with vision if enabled
            if evalEnabled {
                do {
                    let result = try await OpenAIService.shared.evaluateImage(
                        imageData: data,
                        word: wordSerbian,
                        translation: translation,
                        config: config
                    )
                    if !result.ok {
                        MediaStorageService.deleteFile(path: path)
                        continue
                    }
                } catch {
                    // Be lenient on eval failure
                }
            }

            return path
        }

        return nil
    }

    // MARK: - Candidate URL discovery

    func iterCandidateURLs(wordSerbian: String, translation: String, lang: String = "en") -> [String] {
        var queries: [String] = []
        if !translation.isEmpty {
            queries.append(translation)
        }
        if !wordSerbian.trimmingCharacters(in: .whitespaces).isEmpty && wordSerbian != translation {
            queries.append(wordSerbian)
        }

        var urls: [String] = []
        var seen: Set<String> = []

        func push(_ url: String?) {
            guard let url, !url.isEmpty, !seen.contains(url) else { return }
            seen.insert(url)
            urls.append(url)
        }

        // 1. Wikipedia summary/pageimage
        for query in queries {
            let l = query == translation ? lang : "sr"
            if let summaryURL = wikiSummaryImageSync(query: query, lang: l) {
                push(summaryURL)
            }
            if let pageURL = wikiPageimageSync(query: query, lang: l) {
                push(pageURL)
            }
        }

        // 2. Commons search
        if !translation.isEmpty {
            if let commonsURL = commonsSearchSync(query: translation) {
                push(commonsURL)
            }
        }

        return urls
    }

    // MARK: - Wikipedia REST summary

    private func wikiSummaryImageSync(query: String, lang: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        let urlString = "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? synchronousURLRequest(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in ["originalimage", "thumbnail"] {
            if let img = json[key] as? [String: Any], let source = img["source"] as? String {
                return source
            }
        }
        return nil
    }

    // MARK: - Wikipedia pageimage API

    private func wikiPageimageSync(query: String, lang: String) -> String? {
        let urlString = "https://\(lang).wikipedia.org/w/api.php"
        var components = URLComponents(string: urlString)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "original"),
            URLQueryItem(name: "titles", value: query),
            URLQueryItem(name: "redirects", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? synchronousURLRequest(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let pages = queryResult["pages"] as? [String: Any] else {
            return nil
        }

        for (_, page) in pages {
            if let pageDict = page as? [String: Any],
               let original = pageDict["original"] as? [String: Any],
               let source = original["source"] as? String {
                return source
            }
        }
        return nil
    }

    // MARK: - Wikimedia Commons

    private func commonsSearchSync(query: String) -> String? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "filetype:bitmap \"\(query)\""),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url"),
            URLQueryItem(name: "iiurlwidth", value: "800"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? synchronousURLRequest(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let pages = queryResult["pages"] as? [String: Any] else {
            return nil
        }

        for (_, page) in pages {
            if let pageDict = page as? [String: Any],
               let imageInfo = pageDict["imageinfo"] as? [[String: Any]],
               let first = imageInfo.first {
                return (first["thumburl"] as? String) ?? (first["url"] as? String)
            }
        }
        return nil
    }

    // MARK: - Download

    private func download(url urlString: String) async -> (Data, String)? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let ext = extensionFor(url: urlString, contentType: contentType)
            return (data, ext)
        } catch {
            return nil
        }
    }

    private func extensionFor(url: String, contentType: String) -> String {
        let pathExt = (URL(string: url)?.pathExtension ?? "").lowercased()
        if validExtensions.contains(".\(pathExt)") {
            return pathExt == "jpeg" ? "jpg" : pathExt
        }

        if contentType.contains("jpeg") { return "jpg" }
        if contentType.contains("png") { return "png" }
        if contentType.contains("gif") { return "gif" }
        if contentType.contains("webp") { return "webp" }

        return "jpg"
    }

    // MARK: - Synchronous URL request helper (for candidate discovery)

    private func synchronousURLRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = resultError { throw error }
        guard let data = resultData, let response = resultResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}
