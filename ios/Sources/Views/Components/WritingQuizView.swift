import SwiftUI
import PencilKit

public struct WritingQuizView: View {
    public let langCode: String

    @State private var vm = WritingQuizViewModel()
    @State private var canvasView = PKCanvasView()

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var targetStrategy: any LanguageStrategy {
        LanguageRegistry.strategy(for: langCode)
    }

    private var writeColor: Color {
        lang.speakingColor
    }

    public init(langCode: String) {
        self.langCode = langCode
    }

    private var charList: [String] {
        guard let native = vm.currentCard?.native_script else { return [] }
        if targetStrategy.isRTL {
            return [native.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return Array(native.trimmingCharacters(in: .whitespacesAndNewlines)).map(String.init)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header & Review Mode Picker
            headerRail

            if let card = vm.currentCard {
                // Calligraphy Studio Hero Deck
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
                .strokeBorder(writeColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .onAppear {
            vm.loadCards(langCode: langCode)
        }
        .sheet(isPresented: $vm.isCanvasOpen) {
            canvasModalDesk
        }
    }

    // MARK: - 1. Header & Review Mode Rail

    private var headerRail: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.and.scribble")
                    .font(.caption.bold())
                    .foregroundStyle(writeColor)
                Text("CALLIGRAPHY & MOTOR RECALL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Mode Toggle Capsule
            HStack(spacing: 2) {
                ForEach(WritingQuizViewModel.QuizMode.allCases) { mode in
                    let isSelected = vm.mode == mode
                    Button {
                        vm.selectMode(mode)
                    } label: {
                        Text("\(mode.rawValue) (\(mode == .review ? vm.dueCards.count : vm.allCards.count))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? writeColor : Color.clear)
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
                Text(card.translation ?? "Recall Character")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                if let pron = card.pronunciation, !pron.isEmpty {
                    Text("[\(pron)]")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(writeColor)
                }

                Spacer()

                Button {
                    TTSService.shared.speak(text: card.native_script ?? "", langCode: langCode)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption.bold())
                        .foregroundStyle(writeColor)
                        .padding(8)
                        .background(writeColor.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // 3-Column Studio Display
            HStack(alignment: .center, spacing: 14) {
                // Left Column: Radical / Root Satellite
                radicalSatellite

                // Center Column: Calligraphy Character Stage
                calligraphyStage

                // Right Column: Morphology Breakdown
                decompositionSatellite
            }

            // Action: Open Canvas or SM-2 Grading Pod
            if !vm.isPracticeDone {
                Button {
                    canvasView.drawing = PKDrawing()
                    vm.isCanvasOpen = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.tip")
                            .font(.subheadline.bold())
                        Text("Open Writing Canvas")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(writeColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: writeColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            } else {
                sm2GradingArray(card: card)
            }
        }
    }

    // MARK: - 3. Calligraphy Character Stage

    private var calligraphyStage: some View {
        HStack(spacing: 8) {
            ForEach(Array(charList.enumerated()), id: \.offset) { idx, ch in
                let isSelected = idx == vm.activeCharIdx
                let decomp = vm.glyphDetails[ch]

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? writeColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                        )

                    // Grid Overlay
                    if targetStrategy.gridType == .rice {
                        chineseGrid
                    } else if targetStrategy.gridType == .lined {
                        arabicGrid
                    }

                    // Vector Medians / Typographic Character
                    if let medians = decomp?.medians, !medians.isEmpty {
                        GeometryReader { proxy in
                            let scale = min(proxy.size.width, proxy.size.height) / 1024.0
                            ZStack {
                                ForEach(0..<medians.count, id: \.self) { sIdx in
                                    let isVisible = !vm.isPlayingAnimation || (vm.animCharIdx == idx && sIdx < vm.animStrokeIdx) || vm.animCharIdx > idx
                                    let path = StrokeVectorEngine.path(for: medians[sIdx])

                                    path
                                        .trim(from: 0, to: isVisible ? 1.0 : 0.0)
                                        .stroke(writeColor, style: StrokeStyle(lineWidth: 110 * scale, lineCap: .round, lineJoin: .round))
                                        .scaleEffect(y: -1)
                                        .offset(y: proxy.size.height)
                                }
                            }
                        }
                        .padding(10)
                    } else {
                        Text(ch)
                            .font(.system(size: targetStrategy.isRTL ? 42 : 36, weight: .bold, design: targetStrategy.isRTL ? .default : .serif))
                            .foregroundStyle(writeColor)
                    }
                }
                .frame(width: targetStrategy.isRTL ? 140 : 96, height: 96)
                .onTapGesture {
                    vm.activeCharIdx = idx
                }
            }
        }
    }

    private var radicalSatellite: some View {
        let ch = charList.indices.contains(vm.activeCharIdx) ? charList[vm.activeCharIdx] : ""
        let decomp = vm.glyphDetails[ch]

        return VStack(alignment: .leading, spacing: 4) {
            Text(targetStrategy.inspectionLabels.component1.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(decomp?.component1 ?? decomp?.root ?? "—")
                .font(.title3.bold())
                .foregroundStyle(lang.vocabColor)

            if let p = decomp?.phonetic {
                Text(p)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var decompositionSatellite: some View {
        let ch = charList.indices.contains(vm.activeCharIdx) ? charList[vm.activeCharIdx] : ""
        let decomp = vm.glyphDetails[ch]

        return VStack(alignment: .leading, spacing: 4) {
            Text(targetStrategy.inspectionLabels.component2.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(decomp?.component2 ?? "—")
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let hint = decomp?.mnemonic {
                Text(hint)
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 4. Continuous Writing Canvas Modal (PencilKit)

    private var canvasModalDesk: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Prompt strip
                if let card = vm.currentCard {
                    HStack {
                        Text(card.native_script ?? "")
                            .font(.title2.bold())
                        if let p = card.pronunciation {
                            Text("[\(p)]")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(writeColor)
                        }
                        Text("— \(card.translation ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Calligraphy Desk with PencilKit
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))

                    // Ghost guide
                    if vm.showGuidelines, let card = vm.currentCard {
                        Text(card.native_script ?? "")
                            .font(.system(size: 80, weight: .black, design: targetStrategy.isRTL ? .default : .serif))
                            .foregroundStyle(Color.primary.opacity(0.12))
                    }

                    // Native Apple Pencil Canvas
                    WritingCanvasView(
                        canvasView: $canvasView,
                        strokeColor: writeColor,
                        lineWidth: targetStrategy.isRTL ? 12 : 9
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Bottom toolbar: Controls & Done
                HStack {
                    Button {
                        vm.showGuidelines.toggle()
                    } label: {
                        Label(vm.showGuidelines ? "Hide Guide" : "Show Guide", systemImage: vm.showGuidelines ? "eye.slash" : "eye")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)

                    Button {
                        canvasView.undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)

                    Button {
                        canvasView.drawing = PKDrawing()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        vm.isCanvasOpen = false
                        vm.isPracticeDone = true
                        TTSService.shared.speak(text: vm.currentCard?.native_script ?? "", langCode: langCode)
                    } label: {
                        Text("Done Practicing")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(writeColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Writing Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        vm.isCanvasOpen = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 5. SM-2 Grading Pod

    private func sm2GradingArray(card: SRSCard) -> some View {
        HStack(spacing: 6) {
            gradePedal(label: "Again", grade: .again, color: .red, card: card)
            gradePedal(label: "Hard", grade: .hard, color: .orange, card: card)
            gradePedal(label: "Good", grade: .good, color: lang.vocabColor, card: card)
            gradePedal(label: "Easy", grade: .easy, color: Color(red: 129/255, green: 140/255, blue: 248/255), card: card)
        }
    }

    private func gradePedal(label: String, grade: SRSGrade, color: Color, card: SRSCard) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let today = formatter.string(from: Date())

        let projected = SRSEngine.calculateNextState(
            currentRev: card.reps,
            currentInterval: card.interval,
            currentEase: card.ease,
            grade: grade,
            todayStr: today
        )
        let intervalDays = max(1, Int(projected.interval.rounded()))

        return Button {
            Task {
                await vm.submitGrade(grade: grade)
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2.bold())
                Text("+\(intervalDays)d")
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
                .foregroundStyle(writeColor)
            Text("Writing Queue Cleared")
                .font(.headline.bold())
            Text("All scheduled calligraphy and writing reviews are finished for today.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grids

    private var chineseGrid: some View {
        Path { path in
            path.move(to: CGPoint(x: 48, y: 0)); path.addLine(to: CGPoint(x: 48, y: 96))
            path.move(to: CGPoint(x: 0, y: 48)); path.addLine(to: CGPoint(x: 96, y: 48))
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 96, y: 96))
            path.move(to: CGPoint(x: 96, y: 0)); path.addLine(to: CGPoint(x: 0, y: 96))
        }
        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
    }

    private var arabicGrid: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 28)); path.addLine(to: CGPoint(x: 140, y: 28))
            path.move(to: CGPoint(x: 0, y: 48)); path.addLine(to: CGPoint(x: 140, y: 48))
            path.move(to: CGPoint(x: 0, y: 64)); path.addLine(to: CGPoint(x: 140, y: 64))
            path.move(to: CGPoint(x: 0, y: 80)); path.addLine(to: CGPoint(x: 140, y: 80))
        }
        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
    }
}