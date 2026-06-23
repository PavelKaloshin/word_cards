import Foundation
import SwiftData

@Model
final class AppConfig {
    @Attribute(.unique) var id: String

    var masteredThreshold: Int
    var baseIntervalsMinutes: [Int]
    var hardModifier: Double
    var forgetDecayAlpha: Double
    var errorFactorAlpha: Double
    var errorPrior: Double
    var reviewSessionSize: Int
    var maxNewPerSession: Int?
    var reverseProbability: Double
    var dueThresholds: [Double]
    var dueFactors: [Double]
    var typingModeEnabled: Bool
    var typingRelaxedDiacritics: Bool
    var typingHardLevenshteinThreshold: Int
    var alwaysRegenerateExample: Bool
    var openaiModelText: String
    var openaiModelVision: String
    var openaiModelImage: String
    var imageSize: String
    var imageSearchLang: String
    var imageUseLlmFallback: Bool
    var imageEvalEnabled: Bool
    var imageEvalMaxCandidates: Int
    var defaultAlphabetView: String

    init(
        id: String = "singleton",
        masteredThreshold: Int = 3,
        baseIntervalsMinutes: [Int] = [10, 1440, 4320, 10080, 30240, 86400, 259200],
        hardModifier: Double = 0.5,
        forgetDecayAlpha: Double = 0.4,
        errorFactorAlpha: Double = 4.0,
        errorPrior: Double = 0.3,
        reviewSessionSize: Int = 100,
        maxNewPerSession: Int? = nil,
        reverseProbability: Double = 0.5,
        dueThresholds: [Double] = [0.5, 1.0, 2.0, 5.0],
        dueFactors: [Double] = [0.05, 0.3, 1.5, 3.0, 5.0],
        typingModeEnabled: Bool = false,
        typingRelaxedDiacritics: Bool = true,
        typingHardLevenshteinThreshold: Int = 2,
        alwaysRegenerateExample: Bool = false,
        openaiModelText: String = "gpt-4o-mini",
        openaiModelVision: String = "gpt-4o-mini",
        openaiModelImage: String = "dall-e-3",
        imageSize: String = "1024x1024",
        imageSearchLang: String = "en",
        imageUseLlmFallback: Bool = true,
        imageEvalEnabled: Bool = true,
        imageEvalMaxCandidates: Int = 4,
        defaultAlphabetView: String = "both"
    ) {
        self.id = id
        self.masteredThreshold = masteredThreshold
        self.baseIntervalsMinutes = baseIntervalsMinutes
        self.hardModifier = hardModifier
        self.forgetDecayAlpha = forgetDecayAlpha
        self.errorFactorAlpha = errorFactorAlpha
        self.errorPrior = errorPrior
        self.reviewSessionSize = reviewSessionSize
        self.maxNewPerSession = maxNewPerSession
        self.reverseProbability = reverseProbability
        self.dueThresholds = dueThresholds
        self.dueFactors = dueFactors
        self.typingModeEnabled = typingModeEnabled
        self.typingRelaxedDiacritics = typingRelaxedDiacritics
        self.typingHardLevenshteinThreshold = typingHardLevenshteinThreshold
        self.alwaysRegenerateExample = alwaysRegenerateExample
        self.openaiModelText = openaiModelText
        self.openaiModelVision = openaiModelVision
        self.openaiModelImage = openaiModelImage
        self.imageSize = imageSize
        self.imageSearchLang = imageSearchLang
        self.imageUseLlmFallback = imageUseLlmFallback
        self.imageEvalEnabled = imageEvalEnabled
        self.imageEvalMaxCandidates = imageEvalMaxCandidates
        self.defaultAlphabetView = defaultAlphabetView
    }
}
