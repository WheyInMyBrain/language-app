import AVFoundation

@MainActor
public final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(text: String, langCode: String) {
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92

        // Resolve exact Apple locale identifier
        let localeId: String
        if langCode.starts(with: "ar") {
            localeId = "ar-SA"
        } else if langCode.starts(with: "zh") {
            localeId = "zh-CN"
        } else {
            localeId = langCode
        }

        if let voice = AVSpeechSynthesisVoice(language: localeId) {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}