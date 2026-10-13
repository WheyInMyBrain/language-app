import SwiftUI

public enum OmniCardContent: Sendable {
    case vocab(WordItem)
    case ci(ActivityItem)
    case listening(ActivityItem)
    case grammar(ActivityItem)
}

public struct OmniCardView: View {
    public let content: OmniCardContent
    public let index: Int
    public let date: String

    @State private var isExpanded: Bool = false
    @State private var isSpeaking: Bool = false
    @State private var isCopied: Bool = false

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    public init(content: OmniCardContent, index: Int, date: String) {
        self.content = content
        self.index = index
        self.date = date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Content Stage
            cardStage

            // Expandable Audio Drawer
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 14)

                    AudioBarView(
                        lang: lang.code,
                        date: date,
                        category: categoryIdentifier,
                        index: index,
                        accentColor: accentColor
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .transition(.opacity)
            }

            // Drawer Toggle Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(isExpanded ? "Hide audio practice" : (lang.isRTL ? "سجّل النطق" : "Practice pronunciation"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemFill).opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .hoverEffect(.lift)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
        .sensoryFeedback(.success, trigger: isCopied)
    }

    private var categoryIdentifier: String {
        switch content {
        case .vocab: return "vocab"
        case .ci: return "ci"
        case .listening: return "listening"
        case .grammar: return "grammar"
        }
    }

    private var accentColor: Color {
        switch content {
        case .vocab: return lang.vocabColor
        case .ci: return lang.themeColor
        case .listening: return lang.listeningColor
        case .grammar: return lang.grammarColor
        }
    }

    // MARK: - Substage Switcher

    @ViewBuilder
    private var cardStage: some View {
        switch content {
        case .vocab(let word):
            vocabStage(word: word)
        case .ci(let act):
            ciStage(activity: act)
        case .listening(let act):
            listeningStage(activity: act)
        case .grammar(let act):
            grammarStage(activity: act)
        }
    }

    // MARK: - 1. Vocab Stage

    private func vocabStage(word: WordItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Index & TTS
            HStack {
                Text("#\(index)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.15))
                    .foregroundStyle(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Button {
                    speakText(word.native_script)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSpeaking ? .white : accentColor)
                        .frame(width: 28, height: 28)
                        .background(isSpeaking ? accentColor : accentColor.opacity(0.12))
                        .clipShape(Circle())
                        .scaleEffect(isSpeaking ? 1.12 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSpeaking)
                }
                .buttonStyle(.plain)
            }

            // Media Stage Preview
            if let link = word.link, !link.isEmpty {
                MediaStageView(src: link, alt: word.native_script, fallbackChar: word.native_script)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Synchronized Colored Text
            let tokens = lang.colorize(primary: word.native_script, secondary: word.pronunciation ?? "")
            VStack(alignment: .leading, spacing: 2) {
                ColoredTextView(
                    tokens: tokens.primaryTokens,
                    fallbackColor: .primary,
                    isRTL: lang.isRTL
                )
                .font(.system(size: 26, weight: .black))

                if let pron = word.pronunciation, !pron.isEmpty {
                    ColoredTextView(
                        tokens: tokens.secondaryTokens,
                        fallbackColor: .secondary,
                        isRTL: false
                    )
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            }

            if let trans = word.translation, !trans.isEmpty {
                Text(trans)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    // MARK: - 2. CI Video Stage

    private func ciStage(activity: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Text("#\(index)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.15))
                        .foregroundStyle(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Label("CI Video", systemImage: "play.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if let link = activity.link, !link.isEmpty {
                    copyButton(link: link)
                }
            }

            if let link = activity.link, !link.isEmpty {
                MediaStageView(src: link, alt: activity.title, fallbackChar: "▶")
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(activity.title)
                .font(.subheadline.bold())
                .lineLimit(2)
        }
        .padding(14)
    }

    // MARK: - 3. Listening Immersion Stage

    private func listeningStage(activity: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Text("#\(index)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.15))
                        .foregroundStyle(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Label("Listening", systemImage: "headphones")
                        .font(.caption2.bold())
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if let link = activity.link, !link.isEmpty {
                    copyButton(link: link)
                }
            }

            Text(activity.title)
                .font(.subheadline.bold())
                .lineLimit(2)

            if activity.duration_sec > 0 {
                Text("⏱️ \(Int(activity.duration_sec / 60)) minutes logged")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    // MARK: - 4. Grammar Stage

    private func grammarStage(activity: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("#\(index)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.15))
                    .foregroundStyle(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Button {
                    speakText(activity.title)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSpeaking ? .white : accentColor)
                        .frame(width: 28, height: 28)
                        .background(isSpeaking ? accentColor : accentColor.opacity(0.12))
                        .clipShape(Circle())
                        .scaleEffect(isSpeaking ? 1.12 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSpeaking)
                }
                .buttonStyle(.plain)
            }

            Text(activity.title)
                .font(.headline.bold())

            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(14)
    }

    // MARK: - Helpers

    private func copyButton(link: String) -> some View {
        Button {
            UIPasteboard.general.string = link
            isCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                isCopied = false
            }
        } label: {
            Text(isCopied ? "✓ Copied" : "Copy")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func speakText(_ text: String) {
        isSpeaking = true
        TTSService.shared.speak(text: text, langCode: lang.code)
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isSpeaking = false
        }
    }
}