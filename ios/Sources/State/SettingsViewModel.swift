import Foundation
import Observation
import SwiftUI
import UserNotifications

public struct MomentumTier: Codable, Sendable, Equatable {
    public var floor: Int
    public var baseline: Int
    public var ceiling: Int

    public init(floor: Int, baseline: Int, ceiling: Int) {
        self.floor = floor
        self.baseline = baseline
        self.ceiling = ceiling
    }
}

public struct SRSTiers: Codable, Sendable, Equatable {
    public var vision: MomentumTier
    public var listen: MomentumTier
    public var write: MomentumTier

    public init(
        vision: MomentumTier = .init(
            floor: Int(LanguageConfigDefaults.momentum.srs.vision.floor),
            baseline: Int(LanguageConfigDefaults.momentum.srs.vision.baseline),
            ceiling: Int(LanguageConfigDefaults.momentum.srs.vision.ceiling)
        ),
        listen: MomentumTier = .init(
            floor: Int(LanguageConfigDefaults.momentum.srs.listen.floor),
            baseline: Int(LanguageConfigDefaults.momentum.srs.listen.baseline),
            ceiling: Int(LanguageConfigDefaults.momentum.srs.listen.ceiling)
        ),
        write: MomentumTier = .init(
            floor: Int(LanguageConfigDefaults.momentum.srs.write.floor),
            baseline: Int(LanguageConfigDefaults.momentum.srs.write.baseline),
            ceiling: Int(LanguageConfigDefaults.momentum.srs.write.ceiling)
        )
    ) {
        self.vision = vision
        self.listen = listen
        self.write = write
    }
}

@Observable
@MainActor
public final class SettingsViewModel {
    public private(set) var activeLangCode: String = "zh-CN"

    // Theme (Hex string for UI pickers)
    public var selectedThemeHex: String = "#A855F7"
    public var toneColors: [Int: String] = [:]

    // Goals (Reading from LanguageConfigDefaults instance properties)
    public var vocabGoal: Int = LanguageConfigDefaults.goals.vocab
    public var ciGoal: Int = LanguageConfigDefaults.goals.ci
    public var grammarGoal: Int = LanguageConfigDefaults.goals.grammar
    public var listeningMinutesGoal: Int = LanguageConfigDefaults.goals.listening_minutes
    public var speakingMinutesGoal: Int = LanguageConfigDefaults.goals.speaking_minutes

    // Milestones (Reading from LanguageConfigDefaults instance properties)
    public var vocabMilestoneTotal: Int = LanguageConfigDefaults.milestones.vocab_total
    public var listeningMilestoneHours: Double = LanguageConfigDefaults.milestones.listening_hours
    public var speakingMilestoneHours: Double = LanguageConfigDefaults.milestones.speaking_hours

    // Momentum Tiers
    public var listeningTier: MomentumTier = .init(
        floor: Int(LanguageConfigDefaults.momentum.listening.floor),
        baseline: Int(LanguageConfigDefaults.momentum.listening.baseline),
        ceiling: Int(LanguageConfigDefaults.momentum.listening.ceiling)
    )
    public var speakingTier: MomentumTier = .init(
        floor: Int(LanguageConfigDefaults.momentum.speaking.floor),
        baseline: Int(LanguageConfigDefaults.momentum.speaking.baseline),
        ceiling: Int(LanguageConfigDefaults.momentum.speaking.ceiling)
    )
    public var vocabTier: MomentumTier = .init(
        floor: Int(LanguageConfigDefaults.momentum.vocab.floor),
        baseline: Int(LanguageConfigDefaults.momentum.vocab.baseline),
        ceiling: Int(LanguageConfigDefaults.momentum.vocab.ceiling)
    )
    public var srsTiers: SRSTiers = .init()
    public var revisionsTier: MomentumTier = .init(
        floor: Int(LanguageConfigDefaults.momentum.revisions.floor),
        baseline: Int(LanguageConfigDefaults.momentum.revisions.baseline),
        ceiling: Int(LanguageConfigDefaults.momentum.revisions.ceiling)
    )

    // Notification & System States
    public var notificationsEnabled: Bool = false
    public var reminderHour: Int = 19
    public var statusBanner: String? = nil
    public var isSaving: Bool = false

    private var autoSaveTask: Task<Void, Never>?

    public static let themePresets: [(name: String, hex: String)] = [
        ("Ultraviolet", "#A855F7"),
        ("Electric Indigo", "#6366F1"),
        ("Emerald Neo", "#10B981"),
        ("Rose Quartz", "#F43F5E"),
        ("Cyan Pulse", "#06B6D4"),
        ("Amber Forge", "#F59E0B")
    ]

    public init() {}

    // MARK: - Helper to format UInt32 color to Hex String

    private static func uint32ToHex(_ val: UInt32) -> String {
        let rgb = (val >> 8) & 0xFFFFFF
        return String(format: "#%06X", rgb)
    }

    // MARK: - Targeted Language Loading

    public func load(for langCode: String) {
        self.activeLangCode = langCode
        let store = MetadataStore.shared
        let strategy = LanguageRegistry.strategy(for: langCode)
        let config = store.languages[langCode]

        // 1. Language Goals (reading properties: vocab, ci, grammar, listening_minutes, speaking_minutes)
        let g = config?.goals ?? strategy.defaultGoals
        self.vocabGoal = g.vocab
        self.ciGoal = g.ci
        self.grammarGoal = g.grammar
        self.listeningMinutesGoal = g.listening_minutes
        self.speakingMinutesGoal = g.speaking_minutes

        // 2. Language Milestones (reading properties: vocab_total, listening_hours, speaking_hours)
        let m = config?.milestones ?? strategy.defaultMilestones
        self.vocabMilestoneTotal = m.vocab_total
        self.listeningMilestoneHours = m.listening_hours
        self.speakingMilestoneHours = m.speaking_hours

        // 3. Momentum Tiers
        let mom = strategy.defaultMomentum
        self.listeningTier = .init(
            floor: Int(mom.listening.floor),
            baseline: self.listeningMinutesGoal,
            ceiling: Int(mom.listening.ceiling)
        )
        self.speakingTier = .init(
            floor: Int(mom.speaking.floor),
            baseline: self.speakingMinutesGoal,
            ceiling: Int(mom.speaking.ceiling)
        )
        self.vocabTier = .init(
            floor: Int(mom.vocab.floor),
            baseline: self.vocabGoal,
            ceiling: min(10, Int(mom.vocab.ceiling))
        )
        self.srsTiers = .init(
            vision: .init(floor: Int(mom.srs.vision.floor), baseline: Int(mom.srs.vision.baseline), ceiling: Int(mom.srs.vision.ceiling)),
            listen: .init(floor: Int(mom.srs.listen.floor), baseline: Int(mom.srs.listen.baseline), ceiling: Int(mom.srs.listen.ceiling)),
            write: .init(floor: Int(mom.srs.write.floor), baseline: Int(mom.srs.write.baseline), ceiling: Int(mom.srs.write.ceiling))
        )
        self.revisionsTier = .init(
            floor: Int(mom.revisions.floor),
            baseline: Int(mom.revisions.baseline),
            ceiling: Int(mom.revisions.ceiling)
        )

        // 4. Strategy Theme & Tones
        if let themeUInt = config?.colors?.theme?.primary ?? strategy.defaultColors.theme?.primary {
            self.selectedThemeHex = Self.uint32ToHex(themeUInt)
        } else {
            self.selectedThemeHex = "#A855F7"
        }

        self.toneColors = config?.tones ?? strategy.defaultTones

        checkNotificationStatus()
    }

    // MARK: - Debounced Auto-Save

    public func queueAutoSave() {
        autoSaveTask?.cancel()
        isSaving = true

        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            commitSave()
            self.isSaving = false
            self.statusBanner = "Changes saved"

            try? await Task.sleep(for: .seconds(2))
            if self.statusBanner == "Changes saved" {
                self.statusBanner = nil
            }
        }
    }

    // MARK: - Atomic Commit

    private func commitSave() {
        let targetLang = self.activeLangCode
        let store = MetadataStore.shared
        let strategy = LanguageRegistry.strategy(for: targetLang)

        // Synchronize baseline with daily goals
        let resolvedListening = listeningTier.baseline
        let resolvedSpeaking = speakingTier.baseline
        let resolvedVocab = min(10, vocabTier.baseline)

        // Initializer takes: (vocab:grammar:ci:listening:speaking:)
        let newGoals = LanguageGoals(
            vocab: resolvedVocab,
            grammar: grammarGoal,
            ci: ciGoal,
            listening: resolvedListening,
            speaking: resolvedSpeaking
        )

        // Initializer takes: (vocab:listening:speaking:)
        let newMilestones = LanguageMilestones(
            vocab: vocabMilestoneTotal,
            listening: listeningMilestoneHours,
            speaking: speakingMilestoneHours
        )

        // ColorShades takes String: (dark:light:primary:)
        let updatedTheme = ColorShades(
            dark: selectedThemeHex,
            light: selectedThemeHex,
            primary: selectedThemeHex
        )

        let currentColors = store.languages[targetLang]?.colors ?? strategy.defaultColors
        let newColors = LanguageColors(
            theme: updatedTheme,
            streak: currentColors.streak,
            vocab: currentColors.vocab,
            ci: currentColors.ci,
            listening: currentColors.listening,
            speaking: currentColors.speaking,
            grammar: currentColors.grammar,
            flashcard: currentColors.flashcard
        )

        // Update or construct LanguageConfig
        if var cfg = store.languages[targetLang] {
            cfg.goals = newGoals
            cfg.milestones = newMilestones
            cfg.colors = newColors
            cfg.tones = toneColors
            store.languages[targetLang] = cfg
        } else {
            var newConfig = LanguageConfig(code: targetLang, name: strategy.name)
            newConfig.goals = newGoals
            newConfig.milestones = newMilestones
            newConfig.colors = newColors
            newConfig.tones = toneColors
            store.languages[targetLang] = newConfig
        }

        if store.activeLanguage == targetLang {
            ActiveLanguageContext.shared.updateLanguage(code: targetLang)
        }
    }

    // MARK: - Native Notifications

    public func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }

    public func toggleNotifications() {
        if notificationsEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            notificationsEnabled = false
            statusBanner = "Reminders disabled"
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                Task { @MainActor in
                    self.notificationsEnabled = granted
                    if granted {
                        self.scheduleDailyReminder()
                        self.statusBanner = "Study alerts scheduled"
                    } else {
                        self.statusBanner = "Notification permission denied"
                    }
                }
            }
        }
    }

    public func scheduleDailyReminder() {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Daily Immersion Ready"
        content.body = "Complete your target practice session for today."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_language_reminder", content: content, trigger: trigger)

        center.add(request)
    }

    public func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚡ Study Alert Test"
        content.body = "Notifications are active and configured."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}