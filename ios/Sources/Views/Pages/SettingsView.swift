import SwiftUI

public struct SettingsView: View {
    @Bindable var metadata = MetadataStore.shared
    @State private var vm = SettingsViewModel()
    @State private var selectedColorCustom: Color = .purple

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: vm.activeLangCode)
    }

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                // Top Status & Language Switcher Header
                headerBar

                // Section 1: Palette Presets & Accent Glow
                themePaletteSection

                // Section 2: Long-Term Milestones
                milestonesSection

                // Section 3: Adaptive Momentum Sliders
                kineticMomentumSection

                // Section 4: Daily Fixed Activity Goals
                activityGoalsSection

                // Section 5: Phonetic Tone Diacritic Palette (CJK)
                if !vm.toneColors.isEmpty {
                    phoneticTonesSection
                }

                // Section 6: Native iOS Notifications
                notificationsSection

                // Section 7: SQLite Vault & Offline Storage
                dataVaultSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.layoutDirection, targetStrategy.isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            vm.load(for: metadata.activeLanguage)
            selectedColorCustom = Color(hexString: vm.selectedThemeHex)
        }
        .onChange(of: metadata.activeLanguage) { _, newLang in
            vm.load(for: newLang)
            selectedColorCustom = Color(hexString: vm.selectedThemeHex)
        }
        .sensoryFeedback(.selection, trigger: vm.selectedThemeHex)
        .sensoryFeedback(.success, trigger: vm.statusBanner)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(targetStrategy.name) Settings")
                    .font(.title2.bold())

                // Multi-Language Target Switcher
                Menu {
                    ForEach(Array(metadata.languages.keys.sorted()), id: \.self) { code in
                        Button {
                            metadata.activeLanguage = code
                            vm.load(for: code)
                        } label: {
                            HStack {
                                Text(LanguageRegistry.strategy(for: code).name)
                                if code == vm.activeLangCode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Target:")
                        Text(vm.activeLangCode)
                            .bold()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(hexString: vm.selectedThemeHex))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hexString: vm.selectedThemeHex).opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            if vm.isSaving {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Saving...")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(Capsule())
            } else if let banner = vm.statusBanner {
                Text(banner)
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(Color(hexString: vm.selectedThemeHex))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hexString: vm.selectedThemeHex).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Section 1: Palette Presets

    private var themePaletteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader(title: "Language Theme & Aura", icon: "sparkles", color: Color(hexString: vm.selectedThemeHex))
                Spacer()
                ColorPicker("", selection: $selectedColorCustom, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: selectedColorCustom) { _, newColor in
                        // Extract hex from selected color
                        if let components = UIColor(newColor).cgColor.components, components.count >= 3 {
                            let r = Int(components[0] * 255.0)
                            let g = Int(components[1] * 255.0)
                            let b = Int(components[2] * 255.0)
                            let hex = String(format: "#%02X%02X%02X", r, g, b)
                            vm.selectedThemeHex = hex
                            vm.queueAutoSave()
                        }
                    }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(SettingsViewModel.themePresets, id: \.hex) { preset in
                    let isSelected = vm.selectedThemeHex.lowercased() == preset.hex.lowercased()
                    Button {
                        vm.selectedThemeHex = preset.hex
                        selectedColorCustom = Color(hexString: preset.hex)
                        vm.queueAutoSave()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hexString: preset.hex))
                                .frame(width: 14, height: 14)
                            Text(preset.name)
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hexString: preset.hex))
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSelected ? Color(hexString: preset.hex) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Section 2: Long-Term Milestones

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Long-Term Milestones", icon: "trophy.fill", color: .orange)

            VStack(spacing: 12) {
                milestoneRow(title: "Vocabulary Target", unit: "words", value: $vm.vocabMilestoneTotal, step: 50)
                Divider()
                milestoneDoubleRow(title: "Immersion Audio Target", unit: "hours", value: $vm.listeningMilestoneHours, step: 2)
                Divider()
                milestoneDoubleRow(title: "Speech Output Target", unit: "hours", value: $vm.speakingMilestoneHours, step: 1)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func milestoneRow(title: String, unit: String, value: Binding<Int>, step: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Stepper(value: value, step: step, onEditingChanged: { _ in vm.queueAutoSave() }) {
                Text("\(value.wrappedValue) \(unit)")
                    .font(.subheadline.bold().monospacedDigit())
            }
        }
    }

    private func milestoneDoubleRow(title: String, unit: String, value: Binding<Double>, step: Double) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Stepper(value: value, step: step, onEditingChanged: { _ in vm.queueAutoSave() }) {
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.subheadline.bold().monospacedDigit())
            }
        }
    }

    // MARK: - Section 3: Adaptive Momentum Sliders

    private var kineticMomentumSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Kinetic Momentum Tuning", icon: "gauge.with.needle", color: .purple)

            VStack(spacing: 14) {
                momentumTierCard(title: "Listening Immersion", tier: $vm.listeningTier, unit: "m", color: lang.listeningColor)
                momentumTierCard(title: "Speaking Output", tier: $vm.speakingTier, unit: "m", color: lang.speakingColor)
                momentumTierCard(title: "Vocabulary Acquisition", tier: $vm.vocabTier, unit: "w", color: lang.vocabColor)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func momentumTierCard(title: String, tier: Binding<MomentumTier>, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
            }

            HStack(spacing: 12) {
                tierPill(label: "Floor", value: tier.floor, color: .orange)
                tierPill(label: "Baseline", value: tier.baseline, color: color)
                tierPill(label: "Ceiling", value: tier.ceiling, color: .green)
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tierPill(label: String, value: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Stepper(value: value, onEditingChanged: { _ in vm.queueAutoSave() }) {
                Text("\(value.wrappedValue)")
                    .font(.caption.bold().monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Section 4: Daily Activity Targets

    private var activityGoalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Fixed Activity Targets", icon: "target", color: .cyan)

            VStack(spacing: 12) {
                HStack {
                    Text("Daily Comprehensible Input")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $vm.ciGoal, in: 1...10, onEditingChanged: { _ in vm.queueAutoSave() }) {
                        Text("\(vm.ciGoal) vids")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }

                Divider()

                HStack {
                    Text("Daily Grammar Patterns")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $vm.grammarGoal, in: 1...10, onEditingChanged: { _ in vm.queueAutoSave() }) {
                        Text("\(vm.grammarGoal) patterns")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Section 5: Phonetic Tone Palette

    private var phoneticTonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Phonetic Tone Accents", icon: "music.note", color: .pink)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(vm.toneColors.keys.sorted(), id: \.self) { toneNum in
                    let hex = vm.toneColors[toneNum] ?? "#64748b"
                    VStack(spacing: 4) {
                        Text("Tone \(toneNum)")
                            .font(.caption2.bold().monospaced())
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Section 6: Native Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Study Reminders", icon: "bell.badge.fill", color: .yellow)

            Toggle(isOn: Binding(
                get: { vm.notificationsEnabled },
                set: { _ in vm.toggleNotifications() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Study Alerts")
                        .font(.subheadline.bold())
                    Text("Scheduled system notifications for active practice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.notificationsEnabled {
                HStack {
                    Text("Reminder Time")
                        .font(.subheadline)
                    Spacer()
                    Picker("Time", selection: $vm.reminderHour) {
                        Text("5:00 PM").tag(17)
                        Text("6:00 PM").tag(18)
                        Text("7:00 PM (Default)").tag(19)
                        Text("8:00 PM").tag(20)
                        Text("9:00 PM").tag(21)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: vm.reminderHour) { _, _ in
                        vm.scheduleDailyReminder()
                    }
                }

                Button("Send Test Alert") {
                    vm.sendTestNotification()
                }
                .font(.caption.bold())
                .foregroundStyle(Color(hexString: vm.selectedThemeHex))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Section 7: SQLite Vault & Storage

    private var dataVaultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Data Snapshots & Vault", icon: "internaldrive.fill", color: .blue)

            Text("CRDT document history is saved locally and synchronized seamlessly across sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}