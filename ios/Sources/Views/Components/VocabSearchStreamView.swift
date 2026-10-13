import SwiftUI

public struct VocabSearchStreamView: View {
    @Bindable var vocabStore = VocabIndexStore.shared
    @Bindable var metadata = MetadataStore.shared
    public var onSelectDate: (String) -> Void

    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool

    // Reactive aura & layout state
    @State private var breathingHalo: Bool = false

    public init(onSelectDate: @escaping (String) -> Void) {
        self.onSelectDate = onSelectDate
    }

    private var langContext: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var themeColor: Color {
        langContext.themeColor
    }

    private var filteredEntries: [VocabItem] {
        vocabStore.search(query: query)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // MARK: - 1. Glass Micro-Divider Header
            ambientSectionHeader

            // MARK: - 2. Fluid Liquid Glass Search Capsule
            liquidSearchCapsule

            // MARK: - 3. Interactive Holographic Stream
            if filteredEntries.isEmpty {
                fluidEmptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, item in
                            VocabStreamGlassCard(
                                item: item,
                                tokens: langContext.colorize(
                                    primary: item.native_script,
                                    secondary: item.pronunciation ?? ""
                                ),
                                isRTL: langContext.isRTL,
                                accentColor: themeColor,
                                index: index,
                                onSelect: { onSelectDate(item.date) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathingHalo = true
            }
        }
    }

    // MARK: - 1. Ambient Section Header

    private var ambientSectionHeader: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, themeColor.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themeColor)
                    .symbolEffect(.pulse, value: isSearchFocused)

                Text("LEXICON DISCOVERY")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.40))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(themeColor.opacity(0.20), lineWidth: 1)
            )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [themeColor.opacity(0.35), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 2. Fluid Liquid Glass Search Capsule

    private var liquidSearchCapsule: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSearchFocused ? themeColor.opacity(0.20) : Color.clear)
                    .frame(width: 28, height: 28)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSearchFocused ? themeColor : Color.secondary)
            }

            TextField(
                langContext.isRTL ? "البحث بالكلمة، النطق، أو المعنى..." : "Search lexicon by glyph, pinyin or meaning...",
                text: $query
            )
            .focused($isSearchFocused)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .environment(\.layoutDirection, langContext.isRTL ? .rightToLeft : .leftToRight)

            if !query.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        query = ""
                        isSearchFocused = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.8))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // Word Count Capsule (Smooth numeric rolling transitions)
            HStack(spacing: 3) {
                Text("\(filteredEntries.count)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(isSearchFocused ? themeColor : .primary)
                    .contentTransition(.numericText())

                Text(filteredEntries.count == 1 ? "card" : "cards")
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.60))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.85))

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.30))

                if isSearchFocused {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [themeColor.opacity(0.18), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 200
                            )
                        )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isSearchFocused ? 0.90 : 0.60), location: 0.0),
                            .init(color: themeColor.opacity(isSearchFocused ? 0.65 : 0.25), location: 0.40),
                            .init(color: Color.white.opacity(0.12), location: 0.80),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSearchFocused ? 1.5 : 1.1
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        .shadow(color: isSearchFocused ? themeColor.opacity(0.25) : Color.clear, radius: 14, x: 0, y: 4)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSearchFocused)
    }

    // MARK: - 3. Living Liquid Empty State

    private var fluidEmptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .scaleEffect(breathingHalo ? 1.15 : 0.95)

                Image(systemName: query.isEmpty ? "sparkles" : "waveform.and.magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(themeColor)
            }

            VStack(spacing: 3) {
                Text(query.isEmpty ? "Lexicon Canvas Awaiting Entries" : "No Matches in Memory")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(query.isEmpty ? "Add words via Omnibar to watch cards illuminate here." : "No cards match \"\(query)\". Try a different pinyin or translation.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.55))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), themeColor.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Holographic Kinetic Glass Card

private struct VocabStreamGlassCard: View {
    let item: VocabItem
    let tokens: TokenizedPhonetics
    let isRTL: Bool
    let accentColor: Color
    let index: Int
    let onSelect: () -> Void

    // Interactive Drag / Hover Tilt State
    @State private var dragTilt: CGSize = .zero
    @State private var isTouching: Bool = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSelect()
        }) {
            VStack(spacing: 10) {
                // Header Date Glass Pill + Active Beacon
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accentColor)

                        Text(String(item.date.suffix(5)))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .tertiarySystemFill).opacity(0.50))
                    .clipShape(Capsule())

                    Spacer()

                    Circle()
                        .fill(accentColor)
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: accentColor.opacity(0.8), radius: 3)
                }

                // Media Presentation Glass Bezel
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill).opacity(0.35))

                    MediaStageView(
                        src: item.link,
                        alt: item.native_script,
                        fallbackChar: item.native_script
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(3)
                }
                .frame(width: 122, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

                // Colored Glyphs / Script Typography
                VStack(spacing: 3) {
                    ColoredTextView(
                        tokens: tokens.primaryTokens,
                        fallbackColor: .primary,
                        isRTL: isRTL
                    )
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .shadow(color: accentColor.opacity(0.15), radius: 4)

                    ColoredTextView(
                        tokens: tokens.secondaryTokens,
                        fallbackColor: .secondary,
                        isRTL: false
                    )
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: 146, height: 206)
            .background {
                ZStack {
                    // Refractive Glass Chamber
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.88))

                    // Deep Liquid Base
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.28))

                    // Dynamic Chromatic Backdrop
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [accentColor.opacity(isTouching ? 0.24 : 0.10), Color.clear],
                                center: .topLeading,
                                startRadius: 10,
                                endRadius: 140
                            )
                        )
                }
            }
            // Specular Chamfer
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.80), location: 0.0),
                                .init(color: accentColor.opacity(0.40), location: 0.35),
                                .init(color: Color.white.opacity(0.12), location: 0.70),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
            .shadow(color: accentColor.opacity(isTouching ? 0.28 : 0.06), radius: 12, y: 4)
        }
        .buttonStyle(FluidGlassCardButtonStyle())
        .hoverEffect(.lift)
    }
}

// MARK: - Fluid Interactive Spring Button Style

private struct FluidGlassCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .rotation3DEffect(
                .degrees(configuration.isPressed ? -3 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}