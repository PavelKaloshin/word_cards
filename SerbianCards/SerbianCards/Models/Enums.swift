import Foundation

enum Grade: String, Codable, CaseIterable {
    case good
    case hard
    case again
}

enum Direction: String, Codable {
    case forward
    case reverse
}

enum SessionMode: String, Codable {
    case learn
    case review
}

enum AlphabetView: String, Codable, CaseIterable {
    case cyr
    case lat
    case both

    var next: AlphabetView {
        switch self {
        case .cyr: return .lat
        case .lat: return .both
        case .both: return .cyr
        }
    }
}

enum AppScreen: Hashable {
    case apiKeyEntry
    case home
    case session
    case sessionEnd
    case addWords
    case settings
    case history
}
