import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class WritingQuizViewModel {
    public enum QuizMode: String, CaseIterable, Identifiable {
        case review = "Due"
        case cram = "Cram"
        public var id: String { rawValue }
    }

    public var mode: QuizMode = .review
    public var isPracticeDone: Bool = false
    public var isCanvasOpen: Bool = false
    public var showGuidelines: Bool = false
    public var isSubmitting: Bool = false

    // Cards
    public private(set) var dueCards: [SRSCard] = []
    public private(set) var allCards: [SRSCard] = []
    public private(set) var cramIndex: Int = 0

    // Character breakdowns
    public var activeCharIdx: Int = 0
    public var glyphDetails: [String: GlyphDecomposition] = [:]

    // Stroke Animation
    public var isPlayingAnimation: Bool = false
    public var animStrokeIdx: Int = 0
    public var animCharIdx: Int = 0

    private var animationTask: Task<Void, Never>?
    private var glyphFetchTask: Task<Void, Never>?

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

        self.allCards = Array(store.cards.values).shuffled()
        
        let dueWriting = store.getDueItems(todayStr: today, cardType: "writing")
        self.dueCards = dueWriting.isEmpty ? store.getDueItems(todayStr: today) : dueWriting

        self.cramIndex = 0
        self.isPracticeDone = false
        loadGlyphDetailsForCurrent()
    }

    public func selectMode(_ newMode: QuizMode) {
        self.mode = newMode
        self.cramIndex = 0
        self.isPracticeDone = false
        loadGlyphDetailsForCurrent()
    }

    public func loadGlyphDetailsForCurrent() {
        glyphFetchTask?.cancel()
        guard let card = currentCard, let native = card.native_script else { return }
        let chars = Array(native.trimmingCharacters(in: .whitespacesAndNewlines)).map(String.init)
        let currentLang = ActiveLanguageContext.shared.code

        glyphFetchTask = Task { @MainActor in
            for ch in chars {
                guard !Task.isCancelled else { break }
                if self.glyphDetails[ch] == nil {
                    if let decomp = await GlyphLexiconService.shared.fetchGlyph(lang: currentLang, character: ch) {
                        self.glyphDetails[ch] = decomp
                    }
                }
            }
        }
    }

    // MARK: - SM-2 & Rating Actions

    public func submitGrade(grade: SRSGrade) async {
        guard let card = currentCard, let key = card.key else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let currentLang = ActiveLanguageContext.shared.code

        // Directly calls your real YSwift SRSStore.rateCard
        await SRSStore.shared.rateCard(
            langCode: currentLang,
            cardKey: key,
            grade: grade
        )

        if mode == .review {
            if !dueCards.isEmpty {
                dueCards.removeFirst()
            }
        } else {
            cramIndex += 1
        }

        isPracticeDone = false
        loadGlyphDetailsForCurrent()
    }

    public func playStrokeAnimation(charList: [String]) {
        guard !isPlayingAnimation, !charList.isEmpty else { return }
        animationTask?.cancel()
        isPlayingAnimation = true
        animCharIdx = 0
        animStrokeIdx = 0

        animationTask = Task { @MainActor in
            for cIdx in 0..<charList.count {
                self.animCharIdx = cIdx
                let ch = charList[cIdx]
                let count = glyphDetails[ch]?.medians?.count ?? 0

                for sIdx in 0...count {
                    self.animStrokeIdx = sIdx
                    try? await Task.sleep(for: .milliseconds(340))
                    guard !Task.isCancelled else { break }
                }
            }
            self.isPlayingAnimation = false
        }
    }
}