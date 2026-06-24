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

    /// Returns: translation, example_cyr, example_lat, example_translation, pos, verb_group
    func generateTranslationAndExample(word: String, config: AppConfig) async throws -> TranslationResult {
        let prompt = """
        You are a Serbian language tutor for a Russian-speaking student. For the Serbian word/phrase "\(word)", produce:
        1. A concise Russian translation (1–4 words; multiple meanings comma-separated).
        2. A short example sentence (5–10 words) using the word naturally, in Serbian Cyrillic.
        3. The same sentence in Serbian Latin (gajica).
        4. The Russian translation of the sentence.
        5. Part of speech: one of [verb, noun, adjective, adverb, pronoun, numeral, preposition, conjunction, interjection, phrase, other].
        6. If part of speech is "verb", classify the conjugation group based on the 1st-person singular present:
           - "I"   for -am verbs (a-type, e.g. gledati → gledam)
           - "II"  for -im verbs (i-type, e.g. raditi → radim)
           - "III" for -em verbs (e-type, e.g. piti → pijem)
           - "irregular" for fundamentally irregular verbs (e.g. biti, hteti, jesti)
           Otherwise leave empty.

        Respond ONLY with strict JSON. No markdown. Schema:
        {"translation": "...", "example_cyr": "...", "example_lat": "...", "example_translation": "...", "pos": "...", "verb_group": "..."}
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
            exampleTranslation: json["example_translation"] as? String ?? "",
            pos: (json["pos"] as? String ?? "").lowercased(),
            verbGroup: json["verb_group"] as? String ?? ""
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
        You are a Serbian language tutor for a Russian-speaking student. Produce a NEW short example sentence (5–10 words)
        using the Serbian word "\(word)" naturally. Different vocabulary and structure from before.\(avoid)

        Respond ONLY with strict JSON. Schema:
        {"example_cyr": "...", "example_lat": "...", "example_translation": "..."} (example_translation must be in Russian)
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
        You are extracting INDIVIDUAL Serbian VOCABULARY WORDS (lemmas / dictionary \
        forms) from a mixed-language paste (Serbian + Russian + English + chat noise). \
        The user wants WORDS to memorize, NOT phrases or sentences.

        For EVERY content word in the source, output ONE entry in dictionary form:
        - nouns:      nominative singular (e.g. "grad", "kuća", "student")
        - verbs:      infinitive ending in -ti or -ći (e.g. "čitati", "živeti", "ići")
        - adjectives: masculine nominative singular (e.g. "lep", "dobar")
        - adverbs:    as-is (e.g. "uvek", "danas")

        Entry schema:
        - "word": Serbian lemma (translated if source was Russian/English; lemmatized if it was a conjugated/declined form)
        - "translation": corresponding Russian (or English) lemma. Empty string if input was already Serbian without translation.

        Strict rules:
        1. From every Russian/English sentence: translate, then split into Serbian lemmas.
        2. From every Serbian sentence: split into Serbian lemmas.
        3. Strip "1.", "2." numbering from list lines.
        4. Keep order; don't deduplicate.
        5. Serbian Latin (gajica) for translated content by default.

        SKIP these:
        - Stop-words: ja, ti, on, ona, ono, mi, vi, oni, one, sebi, sebe, svoj, ovo, ono, taj, ova, te, ti
        - Prepositions: u, na, sa, s, o, do, od, iz, za, po, pri, pre, posle, pred, kroz, kod, među, nad, pod
        - Conjunctions: i, a, ali, ili, jer, da, što, kako, ako, dok, kada, kad
        - Particles/clitics: se, li, ne, će, sam (auxiliary), je (auxiliary)
        - Numerals written as digits
        - Noise: sender names with timestamps, ￼, blank lines, page numbers

        Idiomatic multi-word phrases that work as a unit MAY be kept whole only if \
        they're genuinely idiomatic and not decomposable (e.g. "žao mi je", "kako si", \
        "boli me ruka"). Default to individual lemmas.

        Few-shot example:

        Source:
        ```
        1. Студент читает.
        2. Я живу в городе.
        3. Žao mi je.
        Stranac
        ```

        Correct output:
        ```
        {"entries": [
          {"word": "student", "translation": "студент"},
          {"word": "čitati", "translation": "читать"},
          {"word": "živeti", "translation": "жить"},
          {"word": "grad", "translation": "город"},
          {"word": "žao mi je", "translation": ""},
          {"word": "stranac", "translation": ""}
        ]}
        ```

        Source text:
        ---
        \(text)
        ---

        Respond ONLY with strict JSON:
        {"entries": [{"word": "<Serbian lemma>", "translation": "<Russian/English lemma or empty>"}, ...]}
        """

        let model = config.openaiModelExtract.isEmpty ? config.openaiModelText : config.openaiModelExtract
        let result = try await chatCompletion(
            model: model,
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
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": config.openaiModelImage,
            "prompt": prompt,
            "n": 1,
        ]
        let model = config.openaiModelImage
        if model.hasPrefix("gpt-image") {
            body["output_format"] = "png"
        } else {
            body["size"] = config.imageSize
            body["response_format"] = "b64_json"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Image gen: no HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
            throw OpenAIError.apiError("Image gen HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first else {
            throw OpenAIError.invalidResponse
        }

        if let b64 = first["b64_json"] as? String {
            return Data(base64Encoded: b64)
        }
        if let urlStr = first["url"] as? String, let imageURL = URL(string: urlStr) {
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            return imageData
        }
        return nil
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

    // MARK: - Conjugations

    func generateConjugations(wordLat: String, translation: String, config: AppConfig) async throws -> ConjugationTable? {
        guard !wordLat.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        let prompt = """
        For the Serbian verb "\(wordLat)" (meaning: "\(translation.isEmpty ? "?" : translation)"), produce \
        the PRESENT TENSE conjugation table. Return BOTH Cyrillic and Latin (gajica) \
        spellings for every form, lowercase, no extra punctuation.

        Persons:
        - 1sg: ja (I)
        - 2sg: ti (you, singular)
        - 3sg: on/ona/ono (he/she/it)
        - 1pl: mi (we)
        - 2pl: vi (you, plural)
        - 3pl: oni/one/ona (they)

        For a multi-word phrase containing a verb, conjugate the main verb (keep \
        auxiliary clitics/pronouns in their place, e.g. "Žao mi je" → 1sg "žao mi je", \
        2sg "žao ti je", etc.).

        Respond ONLY with strict JSON:
        {"1sg": {"cyr": "...", "lat": "..."}, "2sg": {"cyr": "...", "lat": "..."}, \
        "3sg": {"cyr": "...", "lat": "..."}, "1pl": {"cyr": "...", "lat": "..."}, \
        "2pl": {"cyr": "...", "lat": "..."}, "3pl": {"cyr": "...", "lat": "..."}}
        """

        let result = try await chatCompletion(
            model: config.openaiModelText,
            messages: [["role": "user", "content": prompt]],
            temperature: 0.0,
            jsonMode: true
        )

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func parseForm(_ key: String) -> ConjugationForm? {
            guard let entry = json[key] as? [String: Any],
                  let cyr = entry["cyr"] as? String, !cyr.isEmpty,
                  let lat = entry["lat"] as? String, !lat.isEmpty else { return nil }
            return ConjugationForm(cyr: cyr, lat: lat)
        }

        guard let sg1 = parseForm("1sg"), let sg2 = parseForm("2sg"), let sg3 = parseForm("3sg"),
              let pl1 = parseForm("1pl"), let pl2 = parseForm("2pl"), let pl3 = parseForm("3pl") else {
            return nil
        }

        return ConjugationTable(sg1: sg1, sg2: sg2, sg3: sg3, pl1: pl1, pl2: pl2, pl3: pl3)
    }

    // MARK: - Internal

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
    let pos: String
    let verbGroup: String
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
