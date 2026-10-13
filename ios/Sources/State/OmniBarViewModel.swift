import Foundation
import Observation
import SwiftUI

public enum OmniCategory: String, CaseIterable, Identifiable, Sendable {
    case vocab = "Vocab"
    case ci = "CI Video"
    case listening = "Audio"
    case grammar = "Grammar"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .vocab: return "bubble.left.and.bubble.right.fill"
        case .ci: return "play.circle.fill"
        case .listening: return "headphones"
        case .grammar: return "character.book.closed.fill"
        }
    }

    public var keyNum: String {
        switch self {
        case .vocab: return "1"
        case .ci: return "2"
        case .listening: return "3"
        case .grammar: return "4"
        }
    }
}

@Observable
@MainActor
public final class OmniBarViewModel {
    public var activeCategory: OmniCategory = .vocab
    public var isEditMode: Bool = false
    public var selectedIndex: Int = 1
    public var isExpanded: Bool = true
    public var statusMessage: String? = nil

    // 1. Vocab Fields
    public var vocabMediaLink: String = ""
    public var vocabNativeScript: String = "" {
        didSet { handleNativeScriptChanged() }
    }
    public var vocabPronunciation: String = ""
    public var isPronManuallyEdited: Bool = false
    public var vocabDuplicates: [VocabItem] = []

    // 2. CI Video Fields
    public var ciVideoLink: String = ""
    public var ciDuration: String = ""
    public var isFetchingCIDuration: Bool = false

    // 3. Listening Audio Fields
    public var listeningAudioLink: String = ""
    public var listeningDuration: String = ""
    public var isFetchingListDuration: Bool = false
    public var listeningDuplicates: [String] = []

    // 4. Grammar Fields
    public var grammarTitle: String = ""
    public var grammarPronunciation: String = ""
    public var grammarStructure: String = ""
    public var grammarMeaning: String = ""
    public var grammarLink: String = ""

    private var duplicateCheckTask: Task<Void, Never>?

    public init() {}

    // MARK: - Native Script Changes & Duplicate Checking

    private func handleNativeScriptChanged() {
        let text = vocabNativeScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            vocabDuplicates = []
            if !isPronManuallyEdited { vocabPronunciation = "" }
            return
        }

        // Auto-predict pronunciation for Chinese/Pinyin if not manually edited
        let lang = ActiveLanguageContext.shared
        if !isPronManuallyEdited && !lang.isRTL {
            let predicted = PhoneticsFormatter.tokenize(primary: text, secondary: "")
            let syllables = predicted.primaryTokens.map(\.text).joined(separator: " ")
            if !syllables.isEmpty {
                vocabPronunciation = syllables
            }
        }

        // Debounced duplicate detection
        duplicateCheckTask?.cancel()
        duplicateCheckTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let all = VocabIndexStore.shared.entries
            self.vocabDuplicates = all.filter {
                $0.native_script == text && $0.date != DaySessionStore.shared.activeRoom?.components(separatedBy: ":").last
            }
        }
    }

    // MARK: - Category & Mode Switching

    public func selectCategory(_ cat: OmniCategory) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.activeCategory = cat
        self.isEditMode = false
    }

    public func clearInputs() {
        vocabMediaLink = ""
        vocabNativeScript = ""
        vocabPronunciation = ""
        isPronManuallyEdited = false
        vocabDuplicates = []

        ciVideoLink = ""
        ciDuration = ""

        listeningAudioLink = ""
        listeningDuration = ""
        listeningDuplicates = []

        grammarTitle = ""
        grammarPronunciation = ""
        grammarStructure = ""
        grammarMeaning = ""
        grammarLink = ""
    }

    public func populateForEdit(index: Int) {
        self.selectedIndex = index
        let store = DaySessionStore.shared

        switch activeCategory {
        case .vocab:
            if let word = store.words.first(where: { $0.word_index == index }) {
                vocabMediaLink = word.link ?? ""
                vocabNativeScript = word.native_script
                vocabPronunciation = word.pronunciation ?? ""
                isPronManuallyEdited = true
            }
        case .ci:
            if let item = store.activities.first(where: { $0.activity_type == .ci && $0.item_index == index }) {
                ciVideoLink = item.link ?? ""
                ciDuration = item.duration_sec > 0 ? "\(Int(item.duration_sec / 60))m" : ""
            }
        case .listening:
            if let item = store.activities.first(where: { $0.activity_type == .listening && $0.item_index == index }) {
                listeningAudioLink = item.link ?? ""
                listeningDuration = item.duration_sec > 0 ? "\(Int(item.duration_sec / 60))m" : ""
            }
        case .grammar:
            if let item = store.activities.first(where: { $0.activity_type == .grammar && $0.item_index == index }) {
                grammarTitle = item.title
                grammarMeaning = item.detail ?? ""
                grammarLink = item.link ?? ""
            }
        }
    }

    // MARK: - Submission

    public func submit(dateStr: String) async {
        let store = DaySessionStore.shared
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        switch activeCategory {
        case .vocab:
            let native = vocabNativeScript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !native.isEmpty else {
                showStatus("⚠️ Enter word script")
                return
            }
            let word = WordItem(
                word_index: isEditMode ? selectedIndex : (store.words.count + 1),
                native_script: native,
                pronunciation: vocabPronunciation.isEmpty ? nil : vocabPronunciation,
                translation: nil,
                mnemonic: nil,
                link: vocabMediaLink.isEmpty ? nil : vocabMediaLink
            )
            await store.addWord(word)
            showStatus(isEditMode ? "🔄 Updated #\(selectedIndex)" : "✅ Added Word #\(word.word_index)")
            if !isEditMode { clearInputs() }

        case .ci:
            let link = ciVideoLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.isEmpty else {
                showStatus("⚠️ Enter video URL")
                return
            }
            let dur = parseDurationSec(ciDuration)
            let act = ActivityItem(
                item_index: isEditMode ? selectedIndex : (store.activities.filter { $0.activity_type == .ci }.count + 1),
                activity_type: .ci,
                title: link,
                duration_sec: dur,
                link: link
            )
            await store.addActivity(act)
            showStatus("✅ Added Video")
            if !isEditMode { clearInputs() }

        case .listening:
            let link = listeningAudioLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let dur = parseDurationSec(listeningDuration)
            guard !link.isEmpty || dur > 0 else {
                showStatus("⚠️ Enter audio or duration")
                return
            }
            let act = ActivityItem(
                item_index: isEditMode ? selectedIndex : (store.activities.filter { $0.activity_type == .listening }.count + 1),
                activity_type: .listening,
                title: link.isEmpty ? "Immersion Audio" : link,
                duration_sec: dur,
                link: link.isEmpty ? nil : link
            )
            await store.addActivity(act)
            showStatus("✅ Added Listening Session")
            if !isEditMode { clearInputs() }

        case .grammar:
            let title = grammarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                showStatus("⚠️ Enter grammar pattern")
                return
            }
            let act = ActivityItem(
                item_index: isEditMode ? selectedIndex : (store.activities.filter { $0.activity_type == .grammar }.count + 1),
                activity_type: .grammar,
                title: title,
                detail: grammarMeaning.isEmpty ? nil : grammarMeaning,
                link: grammarLink.isEmpty ? nil : grammarLink
            )
            await store.addActivity(act)
            showStatus("✅ Added Grammar Pattern")
            if !isEditMode { clearInputs() }
        }
    }

    private func showStatus(_ msg: String) {
        self.statusMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.statusMessage == msg {
                self.statusMessage = nil
            }
        }
    }

    private func parseDurationSec(_ input: String) -> Double {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasSuffix("m") {
            let val = Double(clean.dropLast()) ?? 0
            return val * 60.0
        }
        let parts = clean.components(separatedBy: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m * 60.0 + s
        }
        return (Double(clean) ?? 0) * 60.0
    }
}