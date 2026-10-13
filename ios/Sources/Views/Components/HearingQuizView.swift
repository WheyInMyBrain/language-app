import SwiftUI

public struct HearingQuizView: View {
    public let langCode: String

    @State private var vm = HearingQuizViewModel()

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: langCode)
    }

    private var listeningColor: Color {
        lang.listeningColor
    }

    public init(langCode: String) {
        self.langCode = langCode
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header & Review Mode Picker
            headerRail

            if let card = vm.currentCard {
                // Auditory Stage Hero Deck
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
                .strokeBorder(listeningColor.opacity(0.2), lineWidth: 1)
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
                Image(systemName: "headphones")
                    .font(.caption.bold())
                    .foregroundStyle(listeningColor)
                Text(targetStrategy.isRTL ? "ACOUSTIC EAR TRAINER" : "TONE EAR TRAINER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Mode Toggle Capsule
            HStack(spacing: 2) {
                ForEach(HearingQuizViewModel.QuizMode.allCases) { mode in
                    let isSelected = vm.mode == mode
                    Button {
                        vm.selectMode(mode)
                    } label: {
                        Text("\(mode.rawValue) (\(mode == .review ? vm.dueCards.count : vm.allCards.count))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? listeningColor : Color.clear)
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
            // Meta Bar with Speed Capsule
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(card.last_reviewed != nil ? String(card.last_reviewed!.suffix(5)) : "Prompt")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.secondary)

                Spacer()

                // Speed Tuner Capsule
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle")
                        .font(.caption2)
                        .foregroundStyle(listeningColor)

                    Button {
                        vm.adjustSpeed(delta: -0.1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                    }

                    Text(String(format: "%.2fx", vm.ttsRate))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))

                    Button {
                        vm.adjustSpeed(delta: 0.1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(Capsule())

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(card.due_date ?? "Now")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.secondary)
            }

            // Acoustic Waveform & Media Stage Box
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if vm.isRevealed {
                    MediaStageView(
                        src: card.link ?? "",
                        alt: "Acoustic Target Artwork",
                        fallbackChar: card.native_script ?? "🎧"
                    )
                } else {
                    acousticTargetPlaceholder
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Audio & Reveal Controls
            HStack(spacing: 10) {
                Button {
                    vm.playAudio()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.subheadline.bold())
                        Text("Play Audio")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(listeningColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: listeningColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                if !vm.isRevealed {
                    Button {
                        vm.revealWord()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .font(.subheadline.bold())
                            Text("Reveal")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Revealed Answer & SM-2 Pedals
            if vm.isRevealed {
                revealedAnswerSection(card: card)
            }
        }
    }

    private var acousticTargetPlaceholder: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(listeningColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(vm.isPlayingAudio ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: vm.isPlayingAudio)

                Image(systemName: "headphones")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(listeningColor)
                    .symbolEffect(.bounce, value: vm.isPlayingAudio)
            }

            Text(targetStrategy.isRTL ? "Listen for acoustic vowels & consonants" : "Listen closely for tone inflection")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 3. Revealed Answer & SM-2 Grading Pod

    private func revealedAnswerSection(card: SRSCard) -> some View {
        VStack(spacing: 14) {
            // Synchronized Colored Word Banner
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
                    vm.playAudio()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .foregroundStyle(listeningColor)
                        .padding(10)
                        .background(listeningColor.opacity(0.12))
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
            gradePedal(label: "Good", grade: .good, color: lang.vocabColor, card: card)
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
                    .background(listeningColor.opacity(0.12))
                    .foregroundStyle(listeningColor)
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
                .foregroundStyle(listeningColor)
            Text("Queue Cleared for Today")
                .font(.headline.bold())
            Text("All scheduled auditory ear-training cards are completed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}