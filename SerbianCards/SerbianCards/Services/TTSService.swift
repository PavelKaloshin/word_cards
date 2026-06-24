import AVFoundation

/// iOS native TTS wrapper using AVSpeechSynthesizer.
/// Uses Serbian voice (sr-Latn-RS or sr-RS) when available.
final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak the given text in Serbian.
    func speak(_ text: String) {
        guard !text.isEmpty else { return }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Try to find the best Serbian voice
        if let serbianVoice = findSerbianVoice() {
            utterance.voice = serbianVoice
        } else {
            // Fallback: use language code directly
            utterance.voice = AVSpeechSynthesisVoice(language: "sr-Latn-RS")
                ?? AVSpeechSynthesisVoice(language: "sr-RS")
                ?? AVSpeechSynthesisVoice(language: "sr")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0

        // Ensure audio session is active
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.speak(utterance)
    }

    /// List available Serbian voices.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("sr")
        }
    }

    private func findSerbianVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // Prefer enhanced/premium voices
        let serbianVoices = voices.filter { $0.language.hasPrefix("sr") }
        // Prefer Latin variant first, then any Serbian
        return serbianVoices.first { $0.language.contains("Latn") }
            ?? serbianVoices.first
    }
}
