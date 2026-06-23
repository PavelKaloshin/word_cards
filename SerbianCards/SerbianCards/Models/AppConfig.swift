import Foundation
import SwiftData

@Model
final class AppConfig {
    @Attribute(.unique) var id: String = "singleton"

    var masteredThreshold: Int = 3
    var baseIntervalsMinutes: [Int] = [10, 1440, 4320, 10080, 30240, 86400, 259200]
    var hardModifier: Double = 0.5
    var forgetDecayAlpha: Double = 0.4
    var errorFactorAlpha: Double = 4.0
    var errorPrior: Double = 0.3
    var reviewSessionSize: Int = 100
    var maxNewPerSession: Int?
    var reverseProbability: Double = 0.5
    var dueThresholds: [Double] = [0.5, 1.0, 2.0, 5.0]
    var dueFactors: [Double] = [0.05, 0.3, 1.5, 3.0, 5.0]
    var typingModeEnabled: Bool = false
    var typingRelaxedDiacritics: Bool = true
    var typingHardLevenshteinThreshold: Int = 2
    var alwaysRegenerateExample: Bool = false
    var openaiModelText: String = "gpt-5.4-mini"
    var openaiModelVision: String = "gpt-5.4-mini"
    var openaiModelExtract: String = "gpt-5.4"
    var openaiModelImage: String = "gpt-image-2"
    var imageSize: String = "1024x1024"
    var imageSearchLang: String = "en"
    var imageUseLlmFallback: Bool = true
    var imageEvalEnabled: Bool = true
    var imageEvalMaxCandidates: Int = 4
    var defaultAlphabetView: String = "both"

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
        openaiModelText: String = "gpt-5.4-mini",
        openaiModelVision: String = "gpt-5.4-mini",
        openaiModelExtract: String = "gpt-5.4",
        openaiModelImage: String = "gpt-image-2",
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
        self.openaiModelExtract = openaiModelExtract
        self.openaiModelImage = openaiModelImage
        self.imageSize = imageSize
        self.imageSearchLang = imageSearchLang
        self.imageUseLlmFallback = imageUseLlmFallback
        self.imageEvalEnabled = imageEvalEnabled
        self.imageEvalMaxCandidates = imageEvalMaxCandidates
        self.defaultAlphabetView = defaultAlphabetView
    }
}
