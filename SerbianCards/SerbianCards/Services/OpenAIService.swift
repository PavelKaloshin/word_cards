import Foundation

/// Port of backend/llm.py — OpenAI API wrappers via URLSession.
/// All prompts copied verbatim from the Python source.
actor OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    private let baseURL = "https://api.openai.com/v1"

    private func apiKey() -> String? {
        KeychainService.loadAPIKey()
    }

    // MARK: - Health check

    func healthCheck(config: AppConfig) async throws -> String {
        let result = try await chatCompletion(
            model: config.openaiModelText,
            messages: [["role": "user", "content": "Reply with exactly: OK"]],
            temperature: 0.0,
            jsonMode: false
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Translation and example

    /// Returns: translation, example_cyr, example_lat, example_translation
    func generateTranslationAndExample(word: String, config: AppConfig) async throws -> TranslationResult {
        let prompt = """
        You are a Serbian language tutor. For the Serbian word "\(word)", produce:
        1. A concise English translation (1–4 words; multiple meanings comma-separated).
        2. A short example sentence (5–10 words) using the word naturally, in Serbian Cyrillic.
        3. The same sentence in Serbian Latin (gajica).
        4. The English translation of the sentence.

        Respond ONLY with strict JSON. No markdown. Schema:
        {"translation": "...", "example_cyr": "...", "example_lat": "...", "example_translation": "..."}
        """

        let result = try await chatCompletion(
            model: config.openaiModelText,
            messages: [["role": "user", "content": prompt]],
            temperature: 0.7,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse
        }

        return TranslationResult(
            translation: json["translation"] as? String ?? "",
            exampleCyr: json["example_cyr"] as? String ?? "",
            exampleLat: json["example_lat"] as? String ?? "",
            exampleTranslation: json["example_translation"] as? String ?? ""
        )
    }

    // MARK: - New example

    func generateNewExample(word: String, prevExamplesCyr: [String], config: AppConfig) async throws -> ExampleResult {
        var avoid = ""
        if !prevExamplesCyr.isEmpty {
            let bulletList = prevExamplesCyr.suffix(5).map { "- \($0)" }.joined(separator: "\n")
            avoid = "\n\nAvoid reusing these previous examples:\n\(bulletList)"
        }

        let prompt = """
        You are a Serbian language tutor. Produce a NEW short example sentence (5–10 words)
        using the Serbian word "\(word)" naturally. Different vocabulary and structure from before.\(avoid)

        Respond ONLY with strict JSON. Schema:
        {"example_cyr": "...", "example_lat": "...", "example_translation": "..."}
        """

        let result = try await chatCompletion(
            model: config.openaiModelText,
            messages: [["role": "user", "content": prompt]],
            temperature: 0.9,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse
        }

        return ExampleResult(
            exampleCyr: json["example_cyr"] as? String ?? "",
            exampleLat: json["example_lat"] as? String ?? "",
            exampleTranslation: json["example_translation"] as? String ?? ""
        )
    }

    // MARK: - Text extraction

    func extractPhrasesFromText(text: String, config: AppConfig) async throws -> [ExtractedEntry] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let prompt = """
        You are processing text the user copied from a chat to extract Serbian \
        vocabulary they want to learn. The source text contains noise: sender names, \
        timestamps in parentheses, emoji/object replacement chars, blank lines, English \
        commentary, etc. Ignore the noise. Keep only Serbian words and phrases.

        Rules:
        - Preserve the user's original Serbian script (Cyrillic or Latin/gajica).
        - Each entry is one word or one short phrase, exactly as the user wrote it.
        - Never translate — only include "translation" if the SOURCE text shows one \
        (e.g. "kuća — house" or "kuća | house" lines).
        - Don't deduplicate; keep order. The server dedupes later.
        - Skip entries that are obviously not Serbian (English-only, numbers, names).
        - Keep punctuation that's part of the phrase (e.g. "Kako si?").

        Source text:
        ---
        \(text)
        ---

        Respond ONLY with strict JSON:
        {"entries": [{"word": "...", "translation": "..."}, ...]}
        """

        let result = try await chatCompletion(
            model: config.openaiModelText,
            messages: [["role": "user", "content": prompt]],
            temperature: 0.0,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            throw OpenAIError.apiError("Failed to parse GPT response: \(result.prefix(200))")
        }

        return entries.compactMap { entry in
            guard let word = entry["word"] as? String, !word.isEmpty else { return nil }
            return ExtractedEntry(
                word: word,
                translation: entry["translation"] as? String
            )
        }
    }

    // MARK: - Vision OCR

    func extractWordsFromImage(imageData: Data, config: AppConfig) async throws -> [ExtractedEntry] {
        let b64 = imageData.base64EncodedString()
        let prompt = """
        This image contains a list of Serbian vocabulary, possibly with English (or other) translations.
        Extract every Serbian word/phrase and its translation if present.

        Respond ONLY with strict JSON. Schema:
        {"entries": [{"word": "...", "translation": "..."}, ...]}

        If a translation is missing, omit the field. Keep the original Serbian script (Cyrillic or Latin) as-is.
        Do not invent words that aren't visible. Do not deduplicate.
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/png;base64,\(b64)"],
                    ],
                ],
            ]
        ]

        let result = try await chatCompletion(
            model: config.openaiModelVision,
            messages: messages,
            temperature: 0.1,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let word = entry["word"] as? String, !word.isEmpty else { return nil }
            return ExtractedEntry(
                word: word,
                translation: entry["translation"] as? String
            )
        }
    }

    // MARK: - Image generation

    func generateImage(word: String, translation: String, config: AppConfig) async throws -> Data? {
        let visible = translation.isEmpty ? word : translation
        let prompt = """
        A flashcard-style illustration depicting the meaning of '\(visible)'. \
        Centered subject, simple uncluttered background, soft watercolor or flat illustration. \
        CRITICAL: The image MUST NOT contain ANY text, letters, numbers, captions, labels, \
        signs, watermarks, logos, alphabet characters, Cyrillic characters, or any written \
        symbols whatsoever. This is a vocabulary flashcard — text in the image would reveal the \
        answer. Pure visual depiction only.
        """

        guard let key = apiKey() else { throw OpenAIError.noAPIKey }
        let url = URL(string: "\(baseURL)/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.openaiModelImage,
            "prompt": prompt,
            "size": config.imageSize,
            "n": 1,
            "response_format": "b64_json",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIError.apiError("Image generation failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let b64 = first["b64_json"] as? String else {
            return nil
        }

        return Data(base64Encoded: b64)
    }

    // MARK: - Image evaluation

    func evaluateImage(imageData: Data, word: String, translation: String, config: AppConfig) async throws -> ImageEvalResult {
        let b64 = imageData.base64EncodedString()
        let target = translation.isEmpty ? word : translation
        let prompt = """
        You are validating an image for a Serbian-language vocabulary flashcard.
        The card teaches the meaning "\(target)" (Serbian: "\(word)").

        REJECT the image if ANY of these are true:
        1. The image contains visible TEXT, letters, numbers, captions, labels, signs, or
           watermarks — these would reveal the answer to the learner.
        2. The image does not visually depict the meaning "\(target)".
        3. The image is NSFW, gory, or otherwise inappropriate for a learning app.
        4. The image is a screenshot of a webpage, dictionary entry, or text document.

        Otherwise ACCEPT.

        Respond ONLY with strict JSON:
        {"ok": true|false, "reason": "<brief reason if rejected, empty string if accepted>"}
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(b64)",
                            "detail": "low",
                        ],
                    ],
                ],
            ]
        ]

        let result = try await chatCompletion(
            model: config.openaiModelVision,
            messages: messages,
            temperature: 0.0,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ImageEvalResult(ok: true, reason: "eval parse failed, accepting")
        }

        return ImageEvalResult(
            ok: json["ok"] as? Bool ?? true,
            reason: json["reason"] as? String ?? ""
        )
    }

    // MARK: - Private: Chat completion

    private func chatCompletion(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        jsonMode: Bool
    ) async throws -> String {
        guard let key = apiKey() else { throw OpenAIError.noAPIKey }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content
    }
}

// MARK: - Data types

struct TranslationResult {
    let translation: String
    let exampleCyr: String
    let exampleLat: String
    let exampleTranslation: String
}

struct ExampleResult {
    let exampleCyr: String
    let exampleLat: String
    let exampleTranslation: String
}

struct ExtractedEntry {
    let word: String
    let translation: String?
}

struct ImageEvalResult {
    let ok: Bool
    let reason: String
}

enum OpenAIError: Error, LocalizedError {
    case noAPIKey
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenAI API key configured"
        case .apiError(let msg): return msg
        case .invalidResponse: return "Invalid response from OpenAI"
        }
    }
}
