import SwiftUI

public struct OmniBarView: View {
    public let activeDate: String

    @Bindable var dayStore = DaySessionStore.shared
    @State private var vm = OmniBarViewModel()
    @FocusState private var focusedField: FormField?
    @Namespace private var categoryIndicatorNamespace

    private enum FormField: Hashable {
        case vocabLink, vocabNative, vocabPron
        case ciLink, ciDuration
        case listLink, listDuration
        case grammarTitle, grammarMeaning
    }

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    public init(activeDate: String) {
        self.activeDate = activeDate
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Icon Dock + HUD Progress + Expand/Collapse Button
            headerDock

            // Expandable Liquid Form Chamber
            if vm.isExpanded {
                VStack(spacing: 12) {
                    categoryFormChamber
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        ))

                    actionControlsRow
                }
            }
        }
        .padding(12)
        .background {
            ZStack {
                // Layer 1: True High-Pass Frosted Glass
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.85))

                // Layer 2: Deep Translucent Base
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.25))

                // Layer 3: Reactive Atmospheric Glow Halo
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [categoryColor.opacity(0.16), Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 220
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.70), location: 0.0),
                            .init(color: categoryColor.opacity(0.40), location: 0.35),
                            .init(color: Color.white.opacity(0.15), location: 0.70),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        .shadow(color: categoryColor.opacity(0.10), radius: 16, x: 0, y: 4)
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: vm.isExpanded)
        .animation(.spring(response: 0.36, dampingFraction: 0.74), value: vm.activeCategory)
        .sensoryFeedback(.selection, trigger: vm.activeCategory)
        .sensoryFeedback(.impact(weight: .light), trigger: vm.isExpanded)
    }

    private var categoryColor: Color {
        switch vm.activeCategory {
        case .vocab: return lang.vocabColor
        case .ci: return lang.themeColor
        case .listening: return lang.listeningColor
        case .grammar: return lang.grammarColor
        }
    }

    // MARK: - 1. Icon-Only Liquid Segment Dock

    private var headerDock: some View {
        HStack(spacing: 8) {
            // Icon Capsules (No Text)
            HStack(spacing: 4) {
                ForEach(OmniCategory.allCases) { cat in
                    let isSelected = vm.activeCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            vm.selectCategory(cat)
                            if !vm.isExpanded {
                                vm.isExpanded = true
                            }
                        }
                    } label: {
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(categoryColor)
                                    .matchedGeometryEffect(id: "activeOmniCategoryPill", in: categoryIndicatorNamespace)
                                    .shadow(color: categoryColor.opacity(0.40), radius: 8, y: 3)
                            }

                            Image(systemName: cat.icon)
                                .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.50))
                                .symbolEffect(.bounce, value: isSelected)
                        }
                        .frame(width: 38, height: 34)
                    }
                    .buttonStyle(OmniSquishButtonStyle())
                    .hoverEffect(.lift)
                }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.60))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()

            // HUD Progress Readout Badge
            hudBadge

            // Expand / Collapse Chevron Button
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.76)) {
                    vm.isExpanded.toggle()
                }
            } label: {
                Image(systemName: vm.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill).opacity(0.70))
                    .clipShape(Circle())
            }
            .buttonStyle(OmniSquishButtonStyle())
            .hoverEffect(.lift)
        }
    }

    private var hudBadge: some View {
        let (current, target) = currentCategoryCounts
        let pct = target > 0 ? min(1.0, Double(current) / Double(target)) : 0.0

        return HStack(spacing: 6) {
            Circle()
                .fill(categoryColor)
                .frame(width: 6, height: 6)
                .shadow(color: categoryColor.opacity(0.6), radius: 3)

            Text("\(current)/\(target)")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.primary)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))
                Capsule()
                    .fill(categoryColor)
                    .frame(width: max(2, 28.0 * pct))
            }
            .frame(width: 28, height: 4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemFill).opacity(0.50))
        .clipShape(Capsule())
    }

    private var currentCategoryCounts: (Int, Int) {
        let goals = lang.strategy.defaultGoals
        switch vm.activeCategory {
        case .vocab: return (dayStore.words.count, goals.vocab)
        case .ci: return (dayStore.activities.filter { $0.activity_type == .ci }.count, goals.ci)
        case .listening: return (dayStore.activities.filter { $0.activity_type == .listening }.count, 2)
        case .grammar: return (dayStore.activities.filter { $0.activity_type == .grammar }.count, goals.grammar)
        }
    }

    // MARK: - 2. Category Form Chamber

    @ViewBuilder
    private var categoryFormChamber: some View {
        switch vm.activeCategory {
        case .vocab:
            VStack(spacing: 8) {
                inputField(
                    icon: "photo",
                    placeholder: "1. Media link (Image, GIF, WebP)...",
                    text: $vm.vocabMediaLink,
                    field: .vocabLink,
                    nextField: .vocabNative
                )

                // Direction-aware Native Script Input
                HStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .foregroundStyle(categoryColor)
                        .font(.system(size: 13, weight: .semibold))

                    TextField(
                        lang.isRTL ? "2. الكلمة بالنص العربي (كتاب، قهوة)..." : "2. Native script (汉字, word)...",
                        text: $vm.vocabNativeScript
                    )
                    .focused($focusedField, equals: .vocabNative)
                    .font(.subheadline.bold())
                    .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    .onSubmit { focusedField = .vocabPron }

                    if !vm.vocabDuplicates.isEmpty {
                        Text("⚠️ \(vm.vocabDuplicates.count)x")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                inputField(
                    icon: "speaker.wave.2",
                    placeholder: "3. Pronunciation (pinyin / transliteration)...",
                    text: $vm.vocabPronunciation,
                    field: .vocabPron,
                    onCommit: { Task { await vm.submit(dateStr: activeDate) } }
                )
            }

        case .ci:
            VStack(spacing: 8) {
                inputField(
                    icon: "film",
                    placeholder: "1. Video URL (https://youtu.be/...)",
                    text: $vm.ciVideoLink,
                    field: .ciLink,
                    nextField: .ciDuration
                )

                inputField(
                    icon: "clock",
                    placeholder: "2. Duration (e.g. 14:20 or 15m)...",
                    text: $vm.ciDuration,
                    field: .ciDuration,
                    onCommit: { Task { await vm.submit(dateStr: activeDate) } }
                )
            }

        case .listening:
            VStack(spacing: 8) {
                inputField(
                    icon: "headphones",
                    placeholder: "1. Podcast or Audio URL...",
                    text: $vm.listeningAudioLink,
                    field: .listLink,
                    nextField: .listDuration
                )

                inputField(
                    icon: "clock",
                    placeholder: "2. Minutes logged (e.g. 20m, 15:30)...",
                    text: $vm.listeningDuration,
                    field: .listDuration,
                    onCommit: { Task { await vm.submit(dateStr: activeDate) } }
                )
            }

        case .grammar:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .foregroundStyle(categoryColor)
                        .font(.system(size: 13, weight: .semibold))

                    TextField(
                        lang.isRTL ? "1. القاعدة النحوية..." : "1. Grammar Point (e.g. 把字句)...",
                        text: $vm.grammarTitle
                    )
                    .focused($focusedField, equals: .grammarTitle)
                    .font(.subheadline.bold())
                    .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    .onSubmit { focusedField = .grammarMeaning }
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                inputField(
                    icon: "text.alignleft",
                    placeholder: "2. Meaning / Structure explanation...",
                    text: $vm.grammarMeaning,
                    field: .grammarMeaning,
                    onCommit: { Task { await vm.submit(dateStr: activeDate) } }
                )
            }
        }
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: FormField,
        nextField: FormField? = nil,
        onCommit: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(focusedField == field ? categoryColor : Color.secondary)
                .font(.system(size: 13, weight: .semibold))

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    if let nextField {
                        focusedField = nextField
                    } else if let onCommit {
                        onCommit()
                    }
                }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.60))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 3. Action Controls Row

    private var actionControlsRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await vm.submit(dateStr: activeDate) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .black))
                    Text(vm.isEditMode ? "Update #\(vm.selectedIndex)" : "Add")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(categoryColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: categoryColor.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(OmniSquishButtonStyle())
            .hoverEffect(.lift)

            if let msg = vm.statusMessage {
                Text(msg)
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(categoryColor)
                    .transition(.opacity)
            }

            Spacer()

            if !vm.vocabNativeScript.isEmpty || !vm.ciVideoLink.isEmpty || !vm.listeningAudioLink.isEmpty || !vm.grammarTitle.isEmpty {
                Button {
                    vm.clearInputs()
                } label: {
                    Text("Clear")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill).opacity(0.50))
                        .clipShape(Capsule())
                }
                .buttonStyle(OmniSquishButtonStyle())
            }
        }
    }
}

// MARK: - Native Apple Spring Button Style

private struct OmniSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}