import SwiftUI

public struct TodayTasksView: View {
    @Bindable var metadata = MetadataStore.shared
    @Bindable var srs = SRSStore.shared
    public var onSelectDate: (String) -> Void

    @State private var viewModel = TodayTasksViewModel()

    // Interactive Gyro & Spatial State
    private var motion = MotionManager.shared
    @State private var dragOffset: CGSize = .zero
    @State private var isTouchingOrb: Bool = false
    @State private var breathingPhase: Double = 0
    @State private var activeHoverRingId: String? = nil

    private let impactFeedback = UIImpactFeedbackGenerator(style: .rigid)

    public init(onSelectDate: @escaping (String) -> Void) {
        self.onSelectDate = onSelectDate
    }

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var activeTheme: Color {
        if let hoverId = activeHoverRingId,
           let ring = allFiveRings.first(where: { $0.id == hoverId }) {
            return ring.color
        }
        return lang.themeColor
    }

    // Effective spatial tilt combining Hardware Gyro + Screen Dragging
    private var combinedTiltX: Double {
        let gyroPitch = motion.pitch * 26.0
        let dragTilt = Double(-dragOffset.height / 8.5)
        return isTouchingOrb ? dragTilt : gyroPitch
    }

    private var combinedTiltY: Double {
        let gyroRoll = motion.roll * 26.0
        let dragTilt = Double(dragOffset.width / 8.5)
        return isTouchingOrb ? dragTilt : gyroRoll
    }

    // MARK: - The Complete 5-Ring Concentric Array
    // Outer to Inner: Vocab (102) -> CI (86) -> Listening (70) -> Speaking (54) -> Grammar (38)
    private var allFiveRings: [(id: String, radius: CGFloat, stroke: CGFloat, color: Color, pct: Double, current: Double, target: Double, unit: String, icon: String)] {
        let goals = lang.strategy.defaultGoals

        let vocabRing = viewModel.rings.first(where: { $0.id == "vocab" })
        let ciRing = viewModel.rings.first(where: { $0.id == "ci" })
        let listRing = viewModel.rings.first(where: { $0.id == "listening" })
        let speakRing = viewModel.rings.first(where: { $0.id == "speaking" })
        let gramRing = viewModel.rings.first(where: { $0.id == "grammar" })

        return [
            (
                id: "vocab",
                radius: 102,
                stroke: 6.5,
                color: lang.vocabColor,
                pct: vocabRing?.pct ?? 0,
                current: vocabRing?.current ?? 0,
                target: vocabRing?.target ?? Double(goals.vocab),
                unit: vocabRing?.unit ?? "",
                icon: "text.bubble.fill"
            ),
            (
                id: "ci",
                radius: 86,
                stroke: 6.5,
                color: lang.themeColor,
                pct: ciRing?.pct ?? 0,
                current: ciRing?.current ?? 0,
                target: ciRing?.target ?? Double(goals.ci),
                unit: ciRing?.unit ?? "m",
                icon: "play.circle.fill"
            ),
            (
                id: "listening",
                radius: 70,
                stroke: 6.5,
                color: lang.listeningColor,
                pct: listRing?.pct ?? 0,
                current: listRing?.current ?? 0,
                target: listRing?.target ?? 20,
                unit: listRing?.unit ?? "m",
                icon: "headphones"
            ),
            (
                id: "speaking",
                radius: 54,
                stroke: 6.5,
                color: lang.speakingColor,
                pct: speakRing?.pct ?? 0,
                current: speakRing?.current ?? 0,
                target: speakRing?.target ?? 15,
                unit: speakRing?.unit ?? "m",
                icon: "waveform"
            ),
            (
                id: "grammar",
                radius: 38,
                stroke: 6.5,
                color: lang.grammarColor,
                pct: gramRing?.pct ?? 0,
                current: gramRing?.current ?? 0,
                target: gramRing?.target ?? Double(goals.grammar),
                unit: gramRing?.unit ?? "",
                icon: "character.book.closed.fill"
            )
        ]
    }

    public var body: some View {
        VStack(spacing: 20) {
            cyberGlassHeader
            kineticSpatialOrb

            if let manifest = viewModel.manifest {
                triDeckPrismBar(manifest: manifest)
                actionPillsStream(manifest: manifest)
            }
        }
        .padding(22)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.88))

                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.24))

                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                activeTheme.opacity(isTouchingOrb ? 0.35 : 0.18),
                                activeTheme.opacity(0.04),
                                Color.clear
                            ],
                            center: UnitPoint(
                                x: 0.5 + (combinedTiltY / 70.0),
                                y: 0.38 - (combinedTiltX / 70.0)
                            ),
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.85), location: 0.0),
                            .init(color: activeTheme.opacity(0.55), location: 0.35),
                            .init(color: Color.white.opacity(0.18), location: 0.70),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: UnitPoint(
                            x: 0.1 + (combinedTiltY / 100.0),
                            y: 0.1 - (combinedTiltX / 100.0)
                        ),
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.3
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 30, x: 0, y: 14)
        .shadow(color: activeTheme.opacity(0.18), radius: 22, x: 0, y: 8)
        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            recompute()
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                breathingPhase = 1.0
            }
        }
        .onChange(of: metadata.activeLanguage) { _, _ in recompute() }
        .onChange(of: metadata.calendarIndex) { _, _ in recompute() }
        .onChange(of: srs.cards) { _, _ in recompute() }
    }

    private func recompute() {
        viewModel.recompute(
            activeLang: metadata.activeLanguage,
            calendarIndex: metadata.calendarIndex,
            cards: srs.cards
        )
    }

    // MARK: - 1. Cyber Glass Telemetry Header

    private var cyberGlassHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(activeTheme.opacity(0.25))
                        .frame(width: 14, height: 14)
                        .scaleEffect(1.0 + (breathingPhase * 0.35))

                    Circle()
                        .fill(activeTheme)
                        .frame(width: 6, height: 6)
                        .shadow(color: activeTheme.opacity(0.8), radius: 4)
                }

                Text(viewModel.todayLog != nil ? "SYNCED" : "ACTIVE SESSION")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.45))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(activeTheme.opacity(0.35), lineWidth: 1))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(activeTheme)

                Text(viewModel.todayStr)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.35))
            .clipShape(Capsule())
        }
    }

    // MARK: - 2. 5-Ring Gyro-Reactive Hologram Orb

    private var kineticSpatialOrb: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Background Glow Halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                activeTheme.opacity(isTouchingOrb ? 0.40 : 0.20),
                                activeTheme.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 145
                        )
                    )
                    .frame(width: 290, height: 290)
                    .blur(radius: isTouchingOrb ? 24 : 16)
                    .scaleEffect(1.0 + (breathingPhase * 0.08))

                // MARK: Concentric Rings Stack (5 Rings)
                ForEach(allFiveRings, id: \.id) { ring in
                    let isHovered = activeHoverRingId == ring.id
                    let isDimmed = activeHoverRingId != nil && !isHovered

                    ZStack {
                        // Track Bed
                        Circle()
                            .stroke(
                                ring.color.opacity(isDimmed ? 0.04 : 0.14),
                                style: StrokeStyle(lineWidth: ring.stroke, lineCap: .round)
                            )
                            .frame(width: ring.radius * 2, height: ring.radius * 2)

                        // Glowing Arc
                        Circle()
                            .trim(from: 0, to: max(0.005, min(1.0, ring.pct)))
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        ring.color.opacity(0.55),
                                        ring.color,
                                        Color.white.opacity(0.95)
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)
                                ),
                                style: StrokeStyle(
                                    lineWidth: isHovered ? ring.stroke + 2.8 : ring.stroke,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: ring.radius * 2, height: ring.radius * 2)
                            .opacity(isDimmed ? 0.15 : 1.0)
                            .shadow(color: ring.color.opacity(isHovered ? 0.90 : 0.35), radius: isHovered ? 12 : 5)

                        // Leading Comet Bead
                        let angle = (-90.0 + (Double(ring.pct) * 360.0)) * .pi / 180.0
                        let cometX = CGFloat(cos(angle)) * ring.radius
                        let cometY = CGFloat(sin(angle)) * ring.radius

                        Circle()
                            .fill(Color.white)
                            .frame(width: ring.stroke * 0.85, height: ring.stroke * 0.85)
                            .shadow(color: ring.color, radius: isHovered ? 8 : 4)
                            .shadow(color: Color.white, radius: 3)
                            .offset(x: cometX, y: cometY)
                            .opacity(isDimmed ? 0.12 : (ring.pct > 0.02 ? 1.0 : 0.0))
                    }
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHovered)
                    .offset(
                        x: CGFloat(combinedTiltY) * (isHovered ? 0.42 : 0.22),
                        y: CGFloat(combinedTiltX) * (isHovered ? 0.42 : 0.22)
                    )
                }

                // MARK: Compact Micro-HUD Center Lens (32pt)
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.95))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.85), activeTheme.opacity(0.45), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.0
                                )
                        )
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                    VStack(spacing: 0) {
                        if let hoverId = activeHoverRingId,
                           let hovered = allFiveRings.first(where: { $0.id == hoverId }) {
                            Image(systemName: hovered.icon)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(hovered.color)
                                .transition(.scale.combined(with: .opacity))

                            Text("\(Int(hovered.current))")
                                .font(.system(size: 9.5, weight: .black, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        } else {
                            Text("\(viewModel.averagePercentage)%")
                                .font(.system(size: 9.5, weight: .black, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .offset(
                    x: CGFloat(combinedTiltY) * 0.55,
                    y: CGFloat(combinedTiltX) * 0.55
                )
                .scaleEffect(isTouchingOrb ? 1.05 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // MARK: Live Hover Scrubber Physics
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        isTouchingOrb = true
                        dragOffset = val.translation

                        let touchVector = CGPoint(
                            x: val.location.x - center.x,
                            y: val.location.y - center.y
                        )
                        let touchDist = sqrt(touchVector.x * touchVector.x + touchVector.y * touchVector.y)

                        // Proximity check against all 5 rings (radii: 38, 54, 70, 86, 102)
                        var matchedRing: String? = nil
                        for ring in allFiveRings {
                            if abs(ring.radius - touchDist) < 9 {
                                matchedRing = ring.id
                                break
                            }
                        }

                        if matchedRing != activeHoverRingId {
                            activeHoverRingId = matchedRing
                            if matchedRing != nil {
                                impactFeedback.impactOccurred()
                            }
                        }
                    }
                    .onEnded { _ in
                        isTouchingOrb = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            activeHoverRingId = nil
                            dragOffset = .zero
                        }
                    }
            )
        }
        .frame(height: 235)
        .rotation3DEffect(
            .degrees(-combinedTiltX),
            axis: (x: 1, y: 0, z: 0)
        )
        .rotation3DEffect(
            .degrees(combinedTiltY),
            axis: (x: 0, y: 1, z: 0)
        )
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.70), value: combinedTiltX)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.70), value: combinedTiltY)
    }

    // MARK: - 3. Pure Icon + Number Prism Pods

    private func triDeckPrismBar(manifest: DailyMissionManifest) -> some View {
        HStack(spacing: 8) {
            triPrismIconCell(count: manifest.srs.vision, icon: "eye.fill", color: lang.themeColor)
            triPrismIconCell(count: manifest.srs.listen, icon: "headphones", color: lang.listeningColor)
            triPrismIconCell(count: manifest.srs.write, icon: "pencil.tip", color: lang.speakingColor)
        }
    }

    private func triPrismIconCell(count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }

            Text("\(count)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.35))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(count > 0 ? 0.35 : 0.08), lineWidth: 1)
        )
        .shadow(color: color.opacity(count > 0 ? 0.12 : 0), radius: 6, y: 2)
    }

    // MARK: - 4. Floating Holographic Action Stream

    private func actionPillsStream(manifest: DailyMissionManifest) -> some View {
        VStack(spacing: 12) {
            if viewModel.todayLog == nil {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSelectDate(viewModel.todayStr)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.20))
                                .frame(width: 32, height: 32)

                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Launch Today's Canvas")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Log vocabulary, immersion videos, and audio")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [activeTheme, activeTheme.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: activeTheme.opacity(0.35), radius: 12, y: 5)
                }
                .buttonStyle(HyperSquishButtonStyle())
            }

            let combinedTasks = manifest.revisions.filter {
                $0.urgencyCategory == "today" || $0.urgencyCategory == "overdue"
            }
            if !combinedTasks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(combinedTasks) { item in
                            let isOverdue = item.urgencyCategory == "overdue"
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelectDate(item.date)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(isOverdue ? Color.red : lang.vocabColor)
                                        .frame(width: 7, height: 7)
                                        .shadow(color: (isOverdue ? Color.red : lang.vocabColor).opacity(0.8), radius: 4)

                                    Text(item.date)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.primary)

                                    Text("P\(item.revision)")
                                        .font(.system(size: 9, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(uiColor: .tertiarySystemFill).opacity(0.8))
                                        .foregroundStyle(.secondary)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .tertiarySystemFill).opacity(0.40))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        (isOverdue ? Color.red : lang.vocabColor).opacity(0.35),
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(HyperSquishButtonStyle())
                        }
                    }
                }
            }

            if !manifest.unvoiced.surfaced.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(manifest.unvoiced.surfaced) { task in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelectDate(task.date)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(lang.speakingColor)

                                    Text("\(task.date) #\(task.wordIndex)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(lang.speakingColor.opacity(0.14))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(lang.speakingColor.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(HyperSquishButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

private struct HyperSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: configuration.isPressed)
    }
}