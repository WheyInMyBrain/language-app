import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class HearingQuizViewModel {
    public enum QuizMode: String, CaseIterable, Identifiable {
        case review = "Due"
        case cram = "Cram"
        public var id: String { rawValue }
    }

    public var mode: QuizMode = .review
    public var ttsRate: Float = 0.85
    public var isRevealed: Bool = false
    public var isSubmitting: Bool = false
    public var isPlayingAudio: Bool = false

    public private(set) var dueCards: [SRSCard] = []
    public private(set) var allCards: [SRSCard] = []
    public private(set) var cramIndex: Int = 0

    public init() {}

    public var currentCard: SRSCard? {
        switch mode {
        case .review:
            return dueCards.first
        case .cram:
            guard cramIndex < allCards.count else { return nil }
            return allCards[cramIndex]
        }
    }

    public func loadCards(langCode: String) {
        let store = SRSStore.shared
        store.connect(langCode: langCode)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let today = formatter.string(from: Date())

        let allStoredCards = Array(store.cards.values)
        let listeningCards = allStoredCards.filter { $0.card_type == "listening" }
        self.allCards = (listeningCards.isEmpty ? allStoredCards : listeningCards).shuffled()

        let dueListening = store.getDueItems(todayStr: today, cardType: "listening")
        self.dueCards = dueListening.isEmpty ? store.getDueItems(todayStr: today) : dueListening

        self.cramIndex = 0
        self.isRevealed = false
    }

    public func selectMode(_ newMode: QuizMode) {
        self.mode = newMode
        self.cramIndex = 0
        self.isRevealed = false
    }

    public func playAudio() {
        guard let card = currentCard, let text = card.native_script, !text.isEmpty else { return }
        isPlayingAudio = true
        TTSService.shared.speak(
            text: text,
            langCode: ActiveLanguageContext.shared.code
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            self.isPlayingAudio = false
        }
    }

    public func revealWord() {
        self.isRevealed = true
        playAudio()
    }

    public func submitGrade(grade: SRSGrade) async {
        guard let card = currentCard, let key = card.key else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let currentLang = ActiveLanguageContext.shared.code
        await SRSStore.shared.rateCard(langCode: currentLang, cardKey: key, grade: grade)

        if mode == .review {
            if !dueCards.isEmpty {
                dueCards.removeFirst()
            }
        } else {
            cramIndex += 1
        }

        self.isRevealed = false
    }

    public func handleCramFail() {
        if let card = currentCard {
            allCards.append(card)
        }
        cramIndex += 1
        isRevealed = false
    }

    public func handleCramPass() {
        cramIndex += 1
        isRevealed = false
    }

    public func adjustSpeed(delta: Float) {
        let next = ttsRate + delta
        if next >= 0.4 && next <= 1.5 {
            ttsRate = (next * 100).rounded() / 100
        }
    }
}