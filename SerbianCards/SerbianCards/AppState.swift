import Foundation
import SwiftData
import SwiftUI

/// Central app state, drives screen routing and holds the current session.
@Observable
final class AppState {
    var currentScreen: AppScreen = .home
    var activeSession: ActiveSession?
    var currentWord: WordEntry?
    var isFlipped: Bool = false
    var alphabet: AlphabetView = .both
    var showTranslation: Bool = false
    var showExample: Bool = false
    var typingMode: Bool = false
    var typingResult: TypingCheckResult?
    var learnPanelOpen: Bool = false
    var learnProgress: LearnProgress?
    var sessionSummary: SessionSummary?
    var sessionMode: SessionMode?

    /// Toast message shown temporarily
    var toastMessage: String?

    /// Loading state
    var isLoading: Bool = false

    /// Error message for display
    var errorMessage: String?

    // Stats for home screen
    var statsNew: Int = 0
    var statsDue: Int = 0
    var statsTotal: Int = 0
    var statsMastered: Int = 0

    func showToast(_ message: String) {
        toastMessage = message
    }

    func resetSessionState() {
        isFlipped = false
        showTranslation = false
        showExample = false
        typingResult = nil
        learnPanelOpen = false
        learnProgress = nil
    }

    func navigateTo(_ screen: AppScreen) {
        currentScreen = screen
    }
}

/// Result from checking typed input against expected word.
struct TypingCheckResult: Equatable {
    let distance: Int
    let suggestedGrade: Grade
    let expectedCyr: String
    let expectedLat: String
}
