import SwiftUI

public struct WordMixerQuizView: View {
    public let langCode: String
    public var onSelectDate: ((String) -> Void)? = nil

    @State private var vm = WordMixerViewModel()

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: langCode)
    }

    private var themeColor: Color {
        lang.themeColor
    }

    public init(langCode: String, onSelectDate: ((String) -> Void)? = nil) {
        self.langCode = langCode
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header & Control Strip
            headerRail

            // Instruction Subtitle
            instructionSubtitle

            // Cards Horizontal Stage Track
            if vm.pool.isEmpty {
                emptyPoolNotice
            } else {
                cardsHorizontalTrack
            }

            // Bottom Status & Forge Action Bar
            bottomActionBar
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(themeColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .onAppear {
            vm.loadInitialCombination()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: vm.mixedWords.count)
    }

    // MARK: - 1. Header & Controls Rail

    private var headerRail: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "dice.fill")
                    .font(.caption.bold())
                    .foregroundStyle(themeColor)
                Text("SENTENCE FORGE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // View Toggle (Full Card vs Image Only)
            Button {
                vm.showText.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: vm.showText ? "square.stack.3d.up" : "photo")
                        .font(.system(size: 10, weight: .bold))
                    Text(vm.showText ? "Full Card" : "Image Only")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            // Quantity Stepper
            HStack(spacing: 6) {
                Button {
                    vm.adjustCount(delta: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .padding(5)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(vm.selectedCount <= vm.minCount)

                Text("\(vm.selectedCount)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(themeColor)
                    .frame(minWidth: 16)

                Button {
                    vm.adjustCount(delta: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .padding(5)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(vm.selectedCount >= vm.maxCount)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
        }
    }

    // MARK: - 2. Instruction Subtitle

    private var instructionSubtitle: some View {
        HStack {
            Text("Construct a cohesive sentence or dialogue integrating all ")
                .foregroundStyle(.secondary)
            + Text("\(vm.selectedCount)")
                .bold()
                .foregroundColor(themeColor)
            + Text(" active cards below:")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.system(size: 11))
    }

    // MARK: - 3. Horizontal Cards Track

    private var cardsHorizontalTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(vm.mixedWords.enumerated()), id: \.offset) { index, item in
                    mixerCard(item: item, index: index)

                    // Connector '+' Capsule
                    if index < vm.mixedWords.count - 1 {
                        ZStack {
                            Circle()
                                .fill(themeColor.opacity(0.15))
                                .frame(width: 26, height: 26)
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(themeColor)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .environment(\.layoutDirection, targetStrategy.isRTL ? .rightToLeft : .leftToRight)
        }
    }

    private func mixerCard(item: VocabItem, index: Int) -> some View {
        VStack(spacing: 8) {
            // Top Card Header: Index / Date Pill & Speaker
            HStack {
                if !item.date.isEmpty {
                    let date = item.date
                    Button {
                        onSelectDate?(date)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8))
                            Text(String(date.suffix(5)))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("#\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    vm.speak(nativeScript: item.native_script, langCode: langCode)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(vm.speakingWordId == item.native_script ? themeColor : .secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Media Stage Preview
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                MediaStageView(
                    src: item.link ?? "",
                    alt: item.native_script,
                    fallbackChar: item.native_script
                )
            }
            .frame(width: vm.showText ? 144 : 124, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Tokenized Colored Native Script & Pronunciation
            if vm.showText {
                let tokenized = targetStrategy.colorize(
                    primary: item.native_script,
                    secondary: item.pronunciation ?? "",
                    palette: lang.tonePalette
                )

                VStack(spacing: 2) {
                    ColoredTextView(tokens: tokenized.primaryTokens)
                        .font(.system(size: targetStrategy.isRTL ? 18 : 16, weight: .black, design: targetStrategy.isRTL ? .default : .serif))
                        .lineLimit(1)

                    if let pron = item.pronunciation, !pron.isEmpty {
                        ColoredTextView(tokens: tokenized.secondaryTokens)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(width: vm.showText ? 156 : 136)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .hoverEffect(.lift)
    }

    // MARK: - 4. Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(themeColor)
                    .frame(width: 6, height: 6)
                Text("Vault Pool: \(vm.pool.count) active words")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.forgeNewCombination()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text("Forge New Combination")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(themeColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: themeColor.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(vm.pool.isEmpty)
        }
        .padding(.top, 4)
    }

    private var emptyPoolNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Vocabulary Logged")
                .font(.subheadline.bold())
            Text("Add vocabulary cards to your study logs to unlock combinatorial sentence synthesis.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}