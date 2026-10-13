import SwiftUI

public struct QuizPageView: View {
    public let langCode: String
    public var onSelectDate: ((String) -> Void)? = nil

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: langCode)
    }

    private var srs: SRSStore {
        SRSStore.shared
    }

    private var vocabIndex: VocabIndexStore {
        VocabIndexStore.shared
    }

    private var themeColor: Color {
        lang.themeColor
    }

    private var vocabColor: Color {
        lang.vocabColor
    }

    private var listeningColor: Color {
        lang.listeningColor
    }

    private var writingColor: Color {
        lang.speakingColor
    }

    public init(langCode: String, onSelectDate: ((String) -> Void)? = nil) {
        self.langCode = langCode
        self.onSelectDate = onSelectDate
    }

    private var todayStr: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private var visualDue: Int {
        srs.getDueItems(todayStr: todayStr, cardType: "visual").count
    }

    private var audioDue: Int {
        srs.getDueItems(todayStr: todayStr, cardType: "listening").count
    }

    private var totalDue: Int {
        visualDue + audioDue
    }

    private var totalWords: Int {
        vocabIndex.entries.count
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 24) {
                // MARK: - 1. Minimal Vision Glass HUD
                minimalVisionHUD

                // MARK: - 2. Stage 01: Mixer
                VStack(spacing: 12) {
                    minimalStageDivider(
                        icon: "dice.fill",
                        color: themeColor
                    )
                    WordMixerQuizView(langCode: langCode, onSelectDate: onSelectDate)
                }

                // MARK: - 3. Stage 02: Visual Recall
                VStack(spacing: 12) {
                    minimalStageDivider(
                        icon: "eye.fill",
                        color: vocabColor,
                        dueCount: visualDue
                    )
                    VisualQuizView(langCode: langCode)
                }

                // MARK: - 4. Stage 03: Acoustic Recall
                VStack(spacing: 12) {
                    minimalStageDivider(
                        icon: "headphones",
                        color: listeningColor,
                        dueCount: audioDue
                    )
                    HearingQuizView(langCode: langCode)
                }

                // MARK: - 5. Stage 04: Motor Calligraphy
                VStack(spacing: 12) {
                    minimalStageDivider(
                        icon: "pencil.and.scribble",
                        color: writingColor
                    )
                    WritingQuizView(langCode: langCode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            srs.connect(langCode: langCode)
        }
    }

    // MARK: - 1. Minimal Vision Glass HUD

    private var minimalVisionHUD: some View {
        HStack(alignment: .center, spacing: 12) {
            // Live Status Beacon
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(themeColor.opacity(0.20))
                        .frame(width: 12, height: 12)

                    Circle()
                        .fill(themeColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: themeColor.opacity(0.8), radius: 3)
                }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(themeColor)
                    .symbolEffect(.pulse)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.45))
            .clipShape(Capsule())

            Spacer()

            // Due Metric Pill
            HStack(spacing: 6) {
                Image(systemName: totalDue > 0 ? "target" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(totalDue > 0 ? Color.orange : Color.green)

                Text("\(totalDue)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((totalDue > 0 ? Color.orange : Color.green).opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder((totalDue > 0 ? Color.orange : Color.green).opacity(0.35), lineWidth: 1)
            )

            // Lexicon Metric Pill
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themeColor)

                Text("\(totalWords)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.50))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
            )
        }
        .padding(14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.85))

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.28))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.70), location: 0.0),
                            .init(color: themeColor.opacity(0.40), location: 0.35),
                            .init(color: Color.white.opacity(0.12), location: 0.70),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    // MARK: - Minimal Stage Divider

    private func minimalStageDivider(
        icon: String,
        color: Color,
        dueCount: Int? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, color.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(color)

                if let count = dueCount, count > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .shadow(color: color.opacity(0.8), radius: 2)

                        Text("\(count)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.14))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.70))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1)
            )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.35), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
    }
}