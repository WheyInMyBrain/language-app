import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class VisualQuizViewModel {
    public enum QuizMode: String, CaseIterable, Identifiable {
        case review = "Due"
        case cram = "Cram"
        public var id: String { rawValue }
    }

    public var mode: QuizMode = .review
    public var isRevealed: Bool = false
    public var isSubmitting: Bool = false
    public var isSpeaking: Bool = false

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
        let visualCards = allStoredCards.filter { $0.card_type == "visual" }
        self.allCards = (visualCards.isEmpty ? allStoredCards : visualCards).shuffled()

        let dueVisual = store.getDueItems(todayStr: today, cardType: "visual")
        self.dueCards = dueVisual.isEmpty ? store.getDueItems(todayStr: today) : dueVisual

        self.cramIndex = 0
        self.isRevealed = false
    }

    public func selectMode(_ newMode: QuizMode) {
        self.mode = newMode
        self.cramIndex = 0
        self.isRevealed = false
    }

    public func revealAnswer() {
        self.isRevealed = true
        if let card = currentCard, let text = card.native_script {
            speak(text: text)
        }
    }

    public func speak(text: String) {
        isSpeaking = true
        TTSService.shared.speak(text: text, langCode: ActiveLanguageContext.shared.code)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            self.isSpeaking = false
        }
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
}