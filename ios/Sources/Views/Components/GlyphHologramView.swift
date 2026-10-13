import SwiftUI

public struct GlyphHologramView: View {
    public let data: GlyphDecomposition
    public let lang: String
    public var onDismiss: () -> Void

    @State private var currentStroke: Int = 0
    @State private var isAnimating: Bool = false
    @State private var focusedComponent: String? = nil
    @State private var animationTask: Task<Void, Never>?

    private var activeLang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var hasStrokeData: Bool {
        if let medians = data.medians, !medians.isEmpty {
            return true
        }
        return false
    }

    private var isRTL: Bool {
        activeLang.isRTL || lang.hasPrefix("ar")
    }

    public init(data: GlyphDecomposition, lang: String, onDismiss: @escaping () -> Void) {
        self.data = data
        self.lang = lang
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // 1. Header Information Bar
                    headerBar

                    // 2. Main Visualizer Stage (Satellites + Main Viewport)
                    HStack(spacing: 14) {
                        // Left Root / Component 1 Satellite
                        if let comp1 = data.component1, !comp1.isEmpty {
                            GlyphMiniCardView(
                                char: comp1,
                                role: isRTL ? "Root" : "Radical",
                                accentColor: activeLang.vocabColor,
                                lang: lang,
                                isFocused: focusedComponent == "comp1",
                                onSelect: {
                                    focusedComponent = (focusedComponent == "comp1") ? nil : "comp1"
                                }
                            )
                            .frame(maxWidth: 160)
                        }

                        // Center Visual Stage
                        centerStageViewport

                        // Right Pattern / Component 2 Satellite
                        if let comp2 = data.component2, !comp2.isEmpty {
                            GlyphMiniCardView(
                                char: comp2,
                                role: isRTL ? "Pattern" : "Body",
                                accentColor: activeLang.themeColor,
                                lang: lang,
                                isFocused: focusedComponent == "comp2",
                                onSelect: {
                                    focusedComponent = (focusedComponent == "comp2") ? nil : "comp2"
                                }
                            )
                            .frame(maxWidth: 160)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // 3. Morphology Decomposition Equation
                    morphologyEquationBanner

                    // 4. Etymology & Mnemonic Story
                    if let hint = data.mnemonic ?? data.etymology_hint, !hint.isEmpty {
                        mnemonicBanner(hint: hint)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: handlePronounce) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(activeLang.themeColor)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if hasStrokeData {
                playAnimation()
            }
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    // MARK: - 1. Header Bar

    private var headerBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(data.character)
                    .font(.system(size: 48, weight: .black, design: isRTL ? .default : .serif))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    if let phonetic = data.phonetic ?? data.pinyin ?? data.transliteration {
                        Text(phonetic)
                            .font(.title2.bold().monospaced())
                            .foregroundStyle(activeLang.themeColor)
                    }

                    if let def = data.definition {
                        Text(def)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.5)).frame(height: 1)
        }
    }

    // MARK: - 2. Visual Stage Viewport

    private var centerStageViewport: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            if isRTL {
                arabicMizanGrid
            } else {
                chineseRiceGrid
            }

            if let medians = data.medians, !medians.isEmpty {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width, proxy.size.height) / 1024.0

                    ZStack {
                        // Ghost Outline Trace
                        ForEach(0..<medians.count, id: \.self) { i in
                            StrokeVectorEngine.path(for: medians[i])
                                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 80 * scale, lineCap: .round, lineJoin: .round))
                                .scaleEffect(y: -1)
                                .offset(y: proxy.size.height)
                        }

                        // Animated Medians
                        ForEach(0..<medians.count, id: \.self) { i in
                            let isVisible = i < currentStroke
                            let path = StrokeVectorEngine.path(for: medians[i])

                            path
                                .trim(from: 0, to: isVisible ? 1.0 : 0.0)
                                .stroke(activeLang.themeColor, style: StrokeStyle(lineWidth: 100 * scale, lineCap: .round, lineJoin: .round))
                                .scaleEffect(y: -1)
                                .offset(y: proxy.size.height)
                                .animation(.easeInOut(duration: 0.35), value: currentStroke)
                        }
                    }
                }
                .padding(20)

                VStack {
                    HStack {
                        Text("\(min(currentStroke, medians.count))/\(medians.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: playAnimation) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            } else {
                Text(data.character)
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(activeLang.themeColor)
            }
        }
        .frame(width: 220, height: 220)
    }

    private var chineseRiceGrid: some View {
        Path { path in
            path.move(to: CGPoint(x: 110, y: 0))
            path.addLine(to: CGPoint(x: 110, y: 220))
            path.move(to: CGPoint(x: 0, y: 110))
            path.addLine(to: CGPoint(x: 220, y: 110))
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 220, y: 220))
            path.move(to: CGPoint(x: 220, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 220))
        }
        .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private var arabicMizanGrid: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 60))
            path.addLine(to: CGPoint(x: 220, y: 60))
            path.move(to: CGPoint(x: 0, y: 110))
            path.addLine(to: CGPoint(x: 220, y: 110))
            path.move(to: CGPoint(x: 0, y: 145))
            path.addLine(to: CGPoint(x: 220, y: 145))
            path.move(to: CGPoint(x: 0, y: 180))
            path.addLine(to: CGPoint(x: 220, y: 180))
        }
        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    // MARK: - 3. Morphology Equation Banner

    private var morphologyEquationBanner: some View {
        HStack(spacing: 8) {
            if let c1 = data.component1, !c1.isEmpty {
                Text(c1)
                    .font(.headline.bold())
                    .foregroundStyle(activeLang.vocabColor)
                Text("+")
                    .foregroundStyle(.secondary)
            }

            if let c2 = data.component2, !c2.isEmpty {
                Text(c2)
                    .font(.headline.bold())
                    .foregroundStyle(activeLang.themeColor)
            }

            Image(systemName: "arrow.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            Text(data.character)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)

            Spacer()

            if let decomp = data.decomposition, !decomp.isEmpty {
                Text(decomp)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 4. Mnemonic Banner

    private func mnemonicBanner(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Mnemonic", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(activeLang.themeColor)

            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Actions

    private func playAnimation() {
        guard let medians = data.medians, !medians.isEmpty else { return }
        animationTask?.cancel()
        currentStroke = 0
        isAnimating = true

        animationTask = Task { @MainActor in
            for i in 1...medians.count {
                try? await Task.sleep(for: .milliseconds(340))
                guard !Task.isCancelled else { break }
                self.currentStroke = i
            }
            self.isAnimating = false
        }
    }

    private func handlePronounce() {
        TTSService.shared.speak(text: data.character, langCode: lang)
    }
}