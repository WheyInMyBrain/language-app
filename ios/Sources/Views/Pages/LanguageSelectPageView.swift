import SwiftUI

public struct LanguageSelectPageView: View {
    public var onSelectLanguage: (String) -> Void

    @Bindable private var metadata = MetadataStore.shared

    @State private var isModalOpen: Bool = false
    @State private var nameInput: String = ""
    @State private var codeInput: String = ""
    @State private var isCustomCode: Bool = false

    private var activeContext: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var languageList: [LanguageConfig] {
        Array(metadata.languages.values).sorted { $0.name < $1.name }
    }

    public init(onSelectLanguage: @escaping (String) -> Void) {
        self.onSelectLanguage = onSelectLanguage
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // 1. Header Hero Bar
                headerHeroBar

                // 2. Language Cards Grid or Empty State
                if languageList.isEmpty {
                    emptyStateNotice
                } else {
                    languageGrid
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isModalOpen) {
            createLanguageSheet
        }
    }

    // MARK: - 1. Header Hero Bar

    private var headerHeroBar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.purple)

                    Text("TARGET LANGUAGE SELECTION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Choose Workspace")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.primary)

                Text("Select a configured target track to continue your habit pulse, or initialize a brand new language arena.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                resetForm()
                isModalOpen = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.purple)
                        .padding(6)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Add Language")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
        }
        .padding(.bottom, 8)
    }

    // MARK: - 2. Language Grid

    private var languageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
            ForEach(languageList) { lang in
                let color = getLanguageColor(lang)

                Button {
                    onSelectLanguage(lang.code)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        // Top Row: Language Icon, Streak, and BCP Tag
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(color.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                                    )

                                Image(systemName: "globe")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(color)
                            }

                            Spacer()

                            if lang.current_streak > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("\(lang.current_streak)d")
                                        .font(.caption2.bold().monospaced())
                                        .foregroundStyle(.orange)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                            }

                            Text(lang.code)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        // Bottom Row: Name, Strategy Indicator & Forward Arrow
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.name)
                                    .font(.title3.weight(.black))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 4) {
                                    Image(systemName: "safari")
                                        .font(.system(size: 9))
                                        .foregroundStyle(color)
                                    Text("Active Track")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(18)
                    .frame(height: 160)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(color.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
            }
        }
    }

    // MARK: - 3. Create Target Language Sheet

    private var createLanguageSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LANGUAGE NAME")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        TextField("e.g. Japanese, German, Spanish", text: $nameInput)
                            .font(.subheadline)
                            .onChange(of: nameInput) { _, newValue in
                                if !isCustomCode {
                                    codeInput = LanguageCodeHelper.guessCode(for: newValue)
                                }
                            }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("BCP-47 LANGUAGE TAG")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if !isCustomCode && !codeInput.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("auto-detected")
                                }
                                .font(.caption2.bold())
                                .foregroundStyle(.purple)
                            }
                        }

                        TextField("e.g. ja, de, es, zh-CN", text: $codeInput)
                            .font(.subheadline.bold().monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: codeInput) {
                                isCustomCode = true
                            }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Language Attributes")
                } footer: {
                    Text("Registering a new language initializes localized SRS spaced repetition queues and phonetics formatting.")
                }
            }
            .navigationTitle("Add Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isModalOpen = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        handleCreateLanguage()
                    }
                    .bold()
                    .disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty State

    private var emptyStateNotice: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "globe")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 4) {
                Text("No languages configured")
                    .font(.headline.bold())

                Text("Create your first target language track to configure habit rings, SRS schedules, and word banks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button {
                resetForm()
                isModalOpen = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                    Text("Create First Language")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.purple)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: Color.purple.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Helpers

    private func resetForm() {
        nameInput = ""
        codeInput = ""
        isCustomCode = false
    }

    private func handleCreateLanguage() {
        let cleanName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanCode = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanCode.isEmpty {
            cleanCode = LanguageCodeHelper.guessCode(for: cleanName)
        }

        guard !cleanName.isEmpty, !cleanCode.isEmpty else { return }

        let strategy = LanguageRegistry.strategy(for: cleanCode)
        var newConfig = LanguageConfig(code: cleanCode, name: cleanName)
        newConfig.goals = strategy.defaultGoals
        newConfig.milestones = strategy.defaultMilestones
        newConfig.momentum = strategy.defaultMomentum
        newConfig.colors = strategy.defaultColors
        newConfig.tones = strategy.defaultTones

        metadata.languages[cleanCode] = newConfig
        isModalOpen = false

        onSelectLanguage(cleanCode)
    }

    private func getLanguageColor(_ lang: LanguageConfig) -> Color {
        if let theme = lang.colors?.theme {
            return theme.swiftUIColor
        }
        return .purple
    }
}