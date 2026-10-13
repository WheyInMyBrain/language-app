import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class WordMixerViewModel {
    public var selectedCount: Int = 2
    public var showText: Bool = true
    public var mixedWords: [VocabItem] = []
    public var speakingWordId: String? = nil

    public let minCount: Int = 2
    public let maxCount: Int = 10

    public init() {}

    public var pool: [VocabItem] {
        VocabIndexStore.shared.entries
    }

    public func loadInitialCombination() {
        if mixedWords.isEmpty && !pool.isEmpty {
            forgeNewCombination()
        }
    }

    public func forgeNewCombination() {
        guard !pool.isEmpty else {
            mixedWords = []
            return
        }
        let count = min(selectedCount, pool.count)
        self.mixedWords = Array(pool.shuffled().prefix(count))
    }

    public func adjustCount(delta: Int) {
        let next = selectedCount + delta
        if next >= minCount && next <= maxCount {
            selectedCount = next
            forgeNewCombination()
        }
    }

    public func speak(nativeScript: String, langCode: String) {
        speakingWordId = nativeScript
        TTSService.shared.speak(text: nativeScript, langCode: langCode)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            if self.speakingWordId == nativeScript {
                self.speakingWordId = nil
            }
        }
    }
}