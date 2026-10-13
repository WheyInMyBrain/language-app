import SwiftUI

public struct VisualQuizView: View {
    public let langCode: String

    @State private var vm = VisualQuizViewModel()

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: langCode)
    }

    private var vocabColor: Color {
        lang.vocabColor
    }

    public init(langCode: String) {
        self.langCode = langCode
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header & Review Mode Picker
            headerRail

            if let card = vm.currentCard {
                // Visual Recall Stage
                cardHeroDeck(card: card)
            } else {
                emptyQueueState
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(vocabColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .onAppear {
            vm.loadCards(langCode: langCode)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: vm.isRevealed)
    }

    // MARK: - 1. Header & Mode Switcher

    private var headerRail: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.caption.bold())
                    .foregroundStyle(vocabColor)
                Text("VISUAL RECOGNITION STUDIO")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Mode Toggle Capsule
            HStack(spacing: 2) {
                ForEach(VisualQuizViewModel.QuizMode.allCases) { mode in
                    let isSelected = vm.mode == mode
                    Button {
                        vm.selectMode(mode)
                    } label: {
                        Text("\(mode.rawValue) (\(mode == .review ? vm.dueCards.count : vm.allCards.count))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? vocabColor : Color.clear)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
        }
    }

    // MARK: - 2. Card Hero Deck

    private func cardHeroDeck(card: SRSCard) -> some View {
        VStack(spacing: 16) {
            // Meta bar
            HStack {
                Text(card.translation ?? "Visual Prompt")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(card.due_date ?? "Now")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.secondary)
            }

            // Media Stage Arena
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                MediaStageView(
                    src: card.link ?? "",
                    alt: "Visual Recall Prompt",
                    fallbackChar: vm.isRevealed ? (card.native_script ?? "❓") : "❓"
                )
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Reveal Action
            if !vm.isRevealed {
                Button {
                    vm.revealAnswer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .font(.subheadline.bold())
                        Text("Reveal Answer")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(vocabColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: vocabColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            } else {
                revealedAnswerSection(card: card)
            }
        }
    }

    // MARK: - 3. Revealed Answer & SM-2 Grading Pod

    private func revealedAnswerSection(card: SRSCard) -> some View {
        VStack(spacing: 14) {
            // Synchronized Tone-Colored Character Banner
            HStack(spacing: 12) {
                let tokenized = targetStrategy.colorize(
                    primary: card.native_script ?? "",
                    secondary: card.pronunciation ?? "",
                    palette: lang.tonePalette
                )

                VStack(alignment: .leading, spacing: 2) {
                    ColoredTextView(tokens: tokenized.primaryTokens)
                        .font(.system(size: targetStrategy.isRTL ? 34 : 28, weight: .black, design: targetStrategy.isRTL ? .default : .serif))

                    if let pron = card.pronunciation, !pron.isEmpty {
                        ColoredTextView(tokens: tokenized.secondaryTokens)
                            .font(.subheadline.bold().monospaced())
                    }
                }

                Spacer()

                Button {
                    vm.speak(text: card.native_script ?? "")
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(vocabColor)
                        .padding(10)
                        .background(vocabColor.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // SM-2 Review Pedals or Cram Pass/Fail
            if vm.mode == .review {
                sm2GradingArray(card: card)
            } else {
                cramGradingArray
            }

            // Interval / Ease Telemetry
            HStack(spacing: 12) {
                Text("Interval: \(Int(card.interval))d")
                Text("•")
                Text(String(format: "Factor: %.2f", card.ease))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func sm2GradingArray(card: SRSCard) -> some View {
        HStack(spacing: 6) {
            gradePedal(label: "Again", grade: .again, color: .red, card: card)
            gradePedal(label: "Hard", grade: .hard, color: .orange, card: card)
            gradePedal(label: "Good", grade: .good, color: vocabColor, card: card)
            gradePedal(label: "Easy", grade: .easy, color: Color(red: 129/255, green: 140/255, blue: 248/255), card: card)
        }
    }

    private var cramGradingArray: some View {
        HStack(spacing: 10) {
            Button {
                vm.handleCramFail()
            } label: {
                Text("❌ Repeat")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.12))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                vm.handleCramPass()
            } label: {
                Text("✅ Pass")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(vocabColor.opacity(0.12))
                    .foregroundStyle(vocabColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func gradePedal(label: String, grade: SRSGrade, color: Color, card: SRSCard) -> some View {
        let preview = SRSEngine.intervalPreview(
            currentInterval: card.interval,
            currentEase: card.ease,
            grade: grade
        )

        return Button {
            Task {
                await vm.submitGrade(grade: grade)
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2.bold())
                Text("+\(preview)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isSubmitting)
    }

    private var emptyQueueState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(vocabColor)
            Text("Queue Cleared for Today")
                .font(.headline.bold())
            Text("All scheduled visual flashcards are completed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}