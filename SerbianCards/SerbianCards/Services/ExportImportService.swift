import Foundation
import SwiftData
import ZipArchive

/// Export/import entire database as a transferable ZIP bundle.
actor ExportImportService {
    static let shared = ExportImportService()
    private init() {}

    // MARK: - Codable wrappers for export

    struct ExportWord: Codable {
        let id: String
        let wordCyr: String
        let wordLat: String
        let translation: String
        let exampleCyr: String
        let exampleLat: String
        let exampleTranslation: String
        let imagePath: String
        let audioPath: String
        let imageHashHistory: [String]
        let note: String
        let createdAt: String
        let lastSeenAt: String?
        let lastCorrectAt: String?
        let streak: Int
        let totalGood: Int
        let totalHard: Int
        let totalAgain: Int
        let forgetCount: Int
        let history: [AnswerRecord]
    }

    struct ExportSession: Codable {
        let id: String
        let mode: String
        let startedAt: String
        let endedAt: String?
        let results: [SessionResult]
        let summary: SessionSummary
    }

    struct ExportConfig: Codable {
        let masteredThreshold: Int
        let baseIntervalsMinutes: [Int]
        let hardModifier: Double
        let forgetDecayAlpha: Double
        let errorFactorAlpha: Double
        let errorPrior: Double
        let reviewSessionSize: Int
        let maxNewPerSession: Int?
        let reverseProbability: Double
        let dueThresholds: [Double]
        let dueFactors: [Double]
        let typingModeEnabled: Bool
        let typingRelaxedDiacritics: Bool
        let typingHardLevenshteinThreshold: Int
        let alwaysRegenerateExample: Bool
        let openaiModelText: String
        let openaiModelVision: String
        let openaiModelImage: String
        let imageSize: String
        let imageSearchLang: String
        let imageUseLlmFallback: Bool
        let imageEvalEnabled: Bool
        let imageEvalMaxCandidates: Int
        let defaultAlphabetView: String
    }

    // MARK: - Export

    @MainActor
    func exportData(modelContext: ModelContext) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export words
        let wordsDescriptor = FetchDescriptor<WordEntry>()
        let words = (try? modelContext.fetch(wordsDescriptor)) ?? []
        let exportWords = words.map { w in
            ExportWord(
                id: w.id, wordCyr: w.wordCyr, wordLat: w.wordLat,
                translation: w.translation, exampleCyr: w.exampleCyr,
                exampleLat: w.exampleLat, exampleTranslation: w.exampleTranslation,
                imagePath: URL(fileURLWithPath: w.imagePath).lastPathComponent,
                audioPath: URL(fileURLWithPath: w.audioPath).lastPathComponent,
                imageHashHistory: w.imageHashHistory, note: w.note,
                createdAt: w.createdAt, lastSeenAt: w.lastSeenAt,
                lastCorrectAt: w.lastCorrectAt, streak: w.streak,
                totalGood: w.totalGood, totalHard: w.totalHard,
                totalAgain: w.totalAgain, forgetCount: w.forgetCount,
                history: w.history
            )
        }
        let wordsData = try JSONEncoder().encode(exportWords)
        try wordsData.write(to: tempDir.appendingPathComponent("words.json"))

        // Export sessions
        let sessionsDescriptor = FetchDescriptor<SessionRecord>()
        let sessions = (try? modelContext.fetch(sessionsDescriptor)) ?? []
        let exportSessions = sessions.map { s in
            ExportSession(
                id: s.id, mode: s.mode, startedAt: s.startedAt,
                endedAt: s.endedAt, results: s.results, summary: s.summary
            )
        }
        let sessionsData = try JSONEncoder().encode(exportSessions)
        try sessionsData.write(to: tempDir.appendingPathComponent("sessions.json"))

        // Export config
        let configDescriptor = FetchDescriptor<AppConfig>()
        let config = (try? modelContext.fetch(configDescriptor))?.first ?? AppConfig()
        let exportConfig = ExportConfig(
            masteredThreshold: config.masteredThreshold,
            baseIntervalsMinutes: config.baseIntervalsMinutes,
            hardModifier: config.hardModifier,
            forgetDecayAlpha: config.forgetDecayAlpha,
            errorFactorAlpha: config.errorFactorAlpha,
            errorPrior: config.errorPrior,
            reviewSessionSize: config.reviewSessionSize,
            maxNewPerSession: config.maxNewPerSession,
            reverseProbability: config.reverseProbability,
            dueThresholds: config.dueThresholds,
            dueFactors: config.dueFactors,
            typingModeEnabled: config.typingModeEnabled,
            typingRelaxedDiacritics: config.typingRelaxedDiacritics,
            typingHardLevenshteinThreshold: config.typingHardLevenshteinThreshold,
            alwaysRegenerateExample: config.alwaysRegenerateExample,
            openaiModelText: config.openaiModelText,
            openaiModelVision: config.openaiModelVision,
            openaiModelImage: config.openaiModelImage,
            imageSize: config.imageSize,
            imageSearchLang: config.imageSearchLang,
            imageUseLlmFallback: config.imageUseLlmFallback,
            imageEvalEnabled: config.imageEvalEnabled,
            imageEvalMaxCandidates: config.imageEvalMaxCandidates,
            defaultAlphabetView: config.defaultAlphabetView
        )
        let configData = try JSONEncoder().encode(exportConfig)
        try configData.write(to: tempDir.appendingPathComponent("config.json"))

        // Copy media files
        let mediaExportDir = tempDir.appendingPathComponent("media")
        try fm.createDirectory(at: mediaExportDir, withIntermediateDirectories: true)

        let imagesExportDir = mediaExportDir.appendingPathComponent("images")
        try fm.createDirectory(at: imagesExportDir, withIntermediateDirectories: true)

        for word in words {
            if !word.imagePath.isEmpty {
                let sourceURL = URL(fileURLWithPath: word.imagePath)
                if fm.fileExists(atPath: sourceURL.path) {
                    let destURL = imagesExportDir.appendingPathComponent(sourceURL.lastPathComponent)
                    try? fm.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // Create ZIP
        let zipPath = fm.temporaryDirectory.appendingPathComponent("SerbianCards-Export.zip")
        try? fm.removeItem(at: zipPath) // Remove previous export
        let success = SSZipArchive.createZipFile(
            atPath: zipPath.path,
            withContentsOfDirectory: tempDir.path
        )
        try? fm.removeItem(at: tempDir)

        guard success else {
            throw ExportImportError.zipCreationFailed
        }
        return zipPath
    }

    // MARK: - Import

    @MainActor
    func importData(from url: URL, modelContext: ModelContext, merge: Bool) throws {
        let fm = FileManager.default
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Handle direct JSON import (web app migration)
        if url.pathExtension.lowercased() == "json" {
            try importWordsJSON(from: url, modelContext: modelContext, merge: merge)
            return
        }

        // Unzip
        let tempDir = fm.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
        let success = SSZipArchive.unzipFile(atPath: url.path, toDestination: tempDir.path)
        guard success else {
            throw ExportImportError.zipExtractionFailed
        }
        defer { try? fm.removeItem(at: tempDir) }

        // Import words
        let wordsURL = tempDir.appendingPathComponent("words.json")
        if fm.fileExists(atPath: wordsURL.path) {
            let data = try Data(contentsOf: wordsURL)
            let importedWords = try JSONDecoder().decode([ExportWord].self, from: data)

            let existingDescriptor = FetchDescriptor<WordEntry>()
            let existingWords = (try? modelContext.fetch(existingDescriptor)) ?? []
            let existingIds = Set(existingWords.map(\.id))

            for ew in importedWords {
                if merge && existingIds.contains(ew.id) { continue }

                let word = WordEntry(
                    id: ew.id, wordCyr: ew.wordCyr, wordLat: ew.wordLat,
                    translation: ew.translation, exampleCyr: ew.exampleCyr,
                    exampleLat: ew.exampleLat, exampleTranslation: ew.exampleTranslation,
                    imagePath: "", audioPath: "",
                    imageHashHistory: ew.imageHashHistory, note: ew.note,
                    createdAt: ew.createdAt, lastSeenAt: ew.lastSeenAt,
                    lastCorrectAt: ew.lastCorrectAt, streak: ew.streak,
                    totalGood: ew.totalGood, totalHard: ew.totalHard,
                    totalAgain: ew.totalAgain, forgetCount: ew.forgetCount,
                    history: ew.history
                )

                // Copy image if exists
                if !ew.imagePath.isEmpty {
                    let sourceImage = tempDir.appendingPathComponent("media/images/\(ew.imagePath)")
                    if fm.fileExists(atPath: sourceImage.path),
                       let imageData = try? Data(contentsOf: sourceImage),
                       let ext = ew.imagePath.split(separator: ".").last {
                        if let savedPath = MediaStorageService.saveImage(
                            data: imageData, wordId: ew.id, ext: String(ext)
                        ) {
                            word.imagePath = savedPath
                        }
                    }
                }

                modelContext.insert(word)
            }
        }

        // Import sessions
        let sessionsURL = tempDir.appendingPathComponent("sessions.json")
        if fm.fileExists(atPath: sessionsURL.path) {
            let data = try Data(contentsOf: sessionsURL)
            let importedSessions = try JSONDecoder().decode([ExportSession].self, from: data)

            let existingDescriptor = FetchDescriptor<SessionRecord>()
            let existingSessions = (try? modelContext.fetch(existingDescriptor)) ?? []
            let existingIds = Set(existingSessions.map(\.id))

            for es in importedSessions {
                if merge && existingIds.contains(es.id) { continue }
                let record = SessionRecord(
                    id: es.id, mode: es.mode, startedAt: es.startedAt,
                    endedAt: es.endedAt, results: es.results, summary: es.summary
                )
                modelContext.insert(record)
            }
        }

        // Import config
        let configURL = tempDir.appendingPathComponent("config.json")
        if fm.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            let ec = try JSONDecoder().decode(ExportConfig.self, from: data)

            let configDescriptor = FetchDescriptor<AppConfig>()
            let config = (try? modelContext.fetch(configDescriptor))?.first ?? {
                let c = AppConfig()
                modelContext.insert(c)
                return c
            }()

            config.masteredThreshold = ec.masteredThreshold
            config.baseIntervalsMinutes = ec.baseIntervalsMinutes
            config.hardModifier = ec.hardModifier
            config.forgetDecayAlpha = ec.forgetDecayAlpha
            config.errorFactorAlpha = ec.errorFactorAlpha
            config.errorPrior = ec.errorPrior
            config.reviewSessionSize = ec.reviewSessionSize
            config.maxNewPerSession = ec.maxNewPerSession
            config.reverseProbability = ec.reverseProbability
            config.dueThresholds = ec.dueThresholds
            config.dueFactors = ec.dueFactors
            config.typingModeEnabled = ec.typingModeEnabled
            config.typingRelaxedDiacritics = ec.typingRelaxedDiacritics
            config.typingHardLevenshteinThreshold = ec.typingHardLevenshteinThreshold
            config.alwaysRegenerateExample = ec.alwaysRegenerateExample
            config.openaiModelText = ec.openaiModelText
            config.openaiModelVision = ec.openaiModelVision
            config.openaiModelImage = ec.openaiModelImage
            config.imageSize = ec.imageSize
            config.imageSearchLang = ec.imageSearchLang
            config.imageUseLlmFallback = ec.imageUseLlmFallback
            config.imageEvalEnabled = ec.imageEvalEnabled
            config.imageEvalMaxCandidates = ec.imageEvalMaxCandidates
            config.defaultAlphabetView = ec.defaultAlphabetView
        }

        try modelContext.save()
    }

    // MARK: - Web app JSON import

    /// Import words from the web app's words.json format (one-time migration).
    @MainActor
    private func importWordsJSON(from url: URL, modelContext: ModelContext, merge: Bool) throws {
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExportImportError.invalidFormat
        }

        let existingDescriptor = FetchDescriptor<WordEntry>()
        let existingWords = (try? modelContext.fetch(existingDescriptor)) ?? []
        let existingKeys = Set(existingWords.map {
            NormalizeService.normalizeForMatch($0.wordLat)
        })

        // Handle both array format and dict format
        let wordDicts: [[String: Any]]
        if let dict = json as? [String: [String: Any]] {
            wordDicts = Array(dict.values)
        } else if let arr = json["words"] as? [[String: Any]] {
            wordDicts = arr
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            wordDicts = arr
        } else {
            throw ExportImportError.invalidFormat
        }

        for wd in wordDicts {
            let wordCyr = wd["word_cyr"] as? String ?? ""
            let wordLat = wd["word_lat"] as? String ?? ""
            let key = NormalizeService.normalizeForMatch(wordLat)

            if merge && existingKeys.contains(key) { continue }

            let word = WordEntry(
                id: wd["id"] as? String ?? UUID().uuidString,
                wordCyr: wordCyr,
                wordLat: wordLat,
                translation: wd["translation"] as? String ?? "",
                exampleCyr: wd["example_cyr"] as? String ?? "",
                exampleLat: wd["example_lat"] as? String ?? "",
                exampleTranslation: wd["example_translation"] as? String ?? "",
                note: wd["note"] as? String ?? "",
                createdAt: wd["created_at"] as? String ?? ScoringService.nowISO(),
                lastSeenAt: wd["last_seen_at"] as? String,
                lastCorrectAt: wd["last_correct_at"] as? String,
                streak: wd["streak"] as? Int ?? 0,
                totalGood: wd["total_good"] as? Int ?? 0,
                totalHard: wd["total_hard"] as? Int ?? 0,
                totalAgain: wd["total_again"] as? Int ?? 0,
                forgetCount: wd["forget_count"] as? Int ?? 0
            )
            modelContext.insert(word)
        }
        try modelContext.save()
    }
}

enum ExportImportError: Error, LocalizedError {
    case zipCreationFailed
    case zipExtractionFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .zipCreationFailed: return "Failed to create ZIP archive"
        case .zipExtractionFailed: return "Failed to extract ZIP archive"
        case .invalidFormat: return "Invalid data format"
        }
    }
}
