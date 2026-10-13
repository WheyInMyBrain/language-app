import SwiftUI
import Charts

public struct DashboardMetricsView: View {
    @Bindable var metadata = MetadataStore.shared
    @State private var viewModel = DashboardMetricsViewModel()

    // Interactive Selection & Hover States
    @State private var selectedTileId: String? = nil

    public init() {}

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var currentStreak: Int {
        metadata.languages[metadata.activeLanguage]?.current_streak ?? 0
    }

    public var body: some View {
        VStack(spacing: 26) {
            // MARK: - 1. Ambient Glass Section Divider
            ambientDivider(label: "Trajectory & Milestones")

            // MARK: - 2. 6-Tile Liquid Telemetry Bento
            kineticTelemetryBento

            // MARK: - 3. Milestone Velocity Chambers
            milestonesBentoSection

            // MARK: - 4. Living Trajectory Hologram with Icon-Only Bar
            liquidTrajectoryChartSection

            // MARK: - 5. Luminescent Matrix Heatmap with Icon-Only Bar
            liquidConsistencyMatrixSection
        }
        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            syncData()
        }
        .onChange(of: metadata.activeLanguage) { _, _ in syncData() }
        .onChange(of: metadata.calendarIndex) { _, _ in syncData() }
    }

    private func syncData() {
        viewModel.sync(
            activeLang: metadata.activeLanguage,
            calendarIndex: metadata.calendarIndex,
            streak: currentStreak
        )
    }

    // MARK: - Ambient Section Divider

    private func ambientDivider(label: String) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, lang.themeColor.opacity(0.45)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(lang.themeColor)

                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.40))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(lang.themeColor.opacity(0.30), lineWidth: 1)
            )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [lang.themeColor.opacity(0.45), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 2. Kinetic Telemetry Bento

    private var kineticTelemetryBento: some View {
        let a = viewModel.aggregates
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            telemetryTile(
                id: "streak",
                title: "STREAK",
                value: "\(a.streak)d",
                sub: "Active Fire",
                icon: "flame.fill",
                color: .orange
            )
            telemetryTile(
                id: "vocab",
                title: "VOCAB",
                value: "\(a.vocab)",
                sub: "Lexicon",
                icon: "text.bubble.fill",
                color: lang.vocabColor
            )
            telemetryTile(
                id: "grammar",
                title: "GRAMMAR",
                value: "\(a.grammar)",
                sub: "Formulas",
                icon: "character.book.closed.fill",
                color: lang.grammarColor
            )
            telemetryTile(
                id: "ci",
                title: "INPUT CI",
                value: "\(a.ci)",
                sub: "Streams",
                icon: "play.circle.fill",
                color: lang.themeColor
            )
            telemetryTile(
                id: "listen",
                title: "AUDIO",
                value: StatsHelper.formatHoursMins(seconds: a.listenSec),
                sub: "Immersed",
                icon: "headphones",
                color: lang.listeningColor
            )
            telemetryTile(
                id: "speak",
                title: "VOCAL",
                value: StatsHelper.formatHoursMins(seconds: a.speakSec),
                sub: "Voiced",
                icon: "waveform",
                color: lang.speakingColor
            )
        }
    }

    private func telemetryTile(
        id: String,
        title: String,
        value: String,
        sub: String,
        icon: String,
        color: Color
    ) -> some View {
        let isFocused = selectedTileId == id

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                selectedTileId = (selectedTileId == id) ? nil : id
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.numericText())

                HStack {
                    Text(sub)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                    Spacer(minLength: 0)
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .shadow(color: color.opacity(0.8), radius: 3)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.88))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.26))

                    if isFocused {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(0.28), Color.clear],
                                    center: .topLeading,
                                    startRadius: 5,
                                    endRadius: 90
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
                                .init(color: Color.white.opacity(isFocused ? 0.90 : 0.60), location: 0.0),
                                .init(color: color.opacity(isFocused ? 0.60 : 0.20), location: 0.40),
                                .init(color: Color.white.opacity(0.12), location: 0.80),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFocused ? 1.4 : 1.1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 5)
            .shadow(color: isFocused ? color.opacity(0.24) : Color.clear, radius: 14, y: 4)
            .scaleEffect(isFocused ? 1.04 : 1.0)
        }
        .buttonStyle(MetricsSquishButtonStyle())
        .hoverEffect(.lift)
    }

    // MARK: - 3. Milestone Velocity Chambers

    private var milestonesBentoSection: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.milestones) { m in
                VStack(spacing: 10) {
                    HStack(alignment: .center) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(m.color.opacity(0.18))
                                    .frame(width: 34, height: 34)

                                Image(systemName: m.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(m.color)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text("Pace: \(m.pace) • Est: \(m.est)")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Text(m.badge)
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(m.color.opacity(0.18))
                                .foregroundStyle(m.color)
                                .clipShape(Capsule())

                            Text("\(Int(round(m.pct * 100)))%")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }

                    // Fluid Progress Rail with Neon Tip
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let activeWidth = max(8.0, width * min(1.0, max(0.0, m.pct)))

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.60))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [m.color.opacity(0.70), m.color, Color.white.opacity(0.95)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: activeWidth)
                                .shadow(color: m.color.opacity(0.50), radius: 5)
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Spacer()
                        Text("Target: \(m.goalLabel)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
                .padding(15)
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
                                    .init(color: m.color.opacity(0.35), location: 0.35),
                                    .init(color: Color.white.opacity(0.12), location: 0.80),
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
        }
    }

    // MARK: - 4. Living Trajectory Hologram with Icon-Only Bar

    private var liquidTrajectoryChartSection: some View {
        let activeColor = colorForMetricTab(viewModel.activeChartTab)
        return VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(activeColor)

                    Text("TRAJECTORY")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                Spacer()

                // Real-Time Scrubber Readout Capsule
                let displayVal = viewModel.chartPoints.last?.value ?? 0
                Text(viewModel.activeChartTab == .vocab ? "\(Int(displayVal)) words" : String(format: "%.1f hrs", displayVal))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(activeColor)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(activeColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Embedded Native-Style Icon-Only Glass Control Bar
            InlineIconOnlyGlassBar(
                items: MetricTab.allCases,
                selection: $viewModel.activeChartTab,
                colorProvider: { colorForMetricTab($0) },
                iconProvider: { iconForMetricTab($0) }
            )
            .frame(height: 44)

            // Swift Chart Canvas
            if viewModel.chartPoints.isEmpty {
                Text("No activity data to plot curve")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(height: 165)
            } else {
                Chart(viewModel.chartPoints) { pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        y: .value("Total", pt.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: activeColor.opacity(0.48), location: 0.0),
                                .init(color: activeColor.opacity(0.10), location: 0.70),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Total", pt.value)
                    )
                    .foregroundStyle(activeColor)
                    .lineStyle(StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    if let selected = viewModel.selectedChartDate {
                        RuleMark(x: .value("Selected", selected))
                            .foregroundStyle(activeColor.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        PointMark(
                            x: .value("Selected", selected),
                            y: .value("Value", viewModel.chartPoints.first(where: { $0.date == selected })?.value ?? 0)
                        )
                        .symbolSize(60)
                        .foregroundStyle(Color.white)
                    }
                }
                .chartXSelection(value: $viewModel.selectedChartDate)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.20))
                        AxisValueLabel()
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel()
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(height: 165)
            }
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.88))

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.26))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.70), location: 0.0),
                            .init(color: activeColor.opacity(0.40), location: 0.40),
                            .init(color: Color.white.opacity(0.12), location: 0.80),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        .shadow(color: activeColor.opacity(0.18), radius: 16, y: 4)
    }

    // MARK: - 5. Luminescent Matrix Heatmap with Icon-Only Bar

    private var liquidConsistencyMatrixSection: some View {
        let activeColor = colorForMetricTab(viewModel.activeHeatmapTab)
        return VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(activeColor)

                    Text("CONSISTENCY MATRIX")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                Spacer()

                if let inspected = viewModel.inspectedDay {
                    HStack(spacing: 6) {
                        Circle().fill(activeColor).frame(width: 6, height: 6)
                        Text(inspected.date)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                        Text(inspected.label)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(activeColor)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(activeColor.opacity(0.14))
                    .clipShape(Capsule())
                }
            }

            // Embedded Native-Style Icon-Only Glass Control Bar
            InlineIconOnlyGlassBar(
                items: MetricTab.allCases,
                selection: $viewModel.activeHeatmapTab,
                colorProvider: { colorForMetricTab($0) },
                iconProvider: { iconForMetricTab($0) }
            )
            .frame(height: 44)

            // 13 Columns × 7 Days Scroll Stream
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(viewModel.heatmapWeeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 5) {
                            ForEach(week) { day in
                                let isSelected = viewModel.inspectedDay?.date == day.date
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                                        viewModel.inspectedDay = day
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .fill(matrixTileColor(level: day.level, base: activeColor))
                                        .frame(width: 15, height: 15)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                                .strokeBorder(
                                                    isSelected ? Color.white : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .shadow(color: isSelected ? activeColor.opacity(0.85) : Color.clear, radius: 4)
                                        .scaleEffect(isSelected ? 1.25 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }

            // Legend
            HStack {
                Text("Dormant")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(0...4, id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(matrixTileColor(level: lvl, base: activeColor))
                            .frame(width: 9, height: 9)
                    }
                }

                Text("Peak")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.88))

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.26))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.70), location: 0.0),
                            .init(color: activeColor.opacity(0.40), location: 0.40),
                            .init(color: Color.white.opacity(0.12), location: 0.80),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        .shadow(color: activeColor.opacity(0.18), radius: 16, y: 4)
    }

    // MARK: - Color & Icon Providers for MetricTab

    private func colorForMetricTab(_ tab: MetricTab) -> Color {
        switch tab {
        case .vocab: return lang.vocabColor
        case .listening: return lang.listeningColor
        case .speaking: return lang.speakingColor
        @unknown default: return lang.themeColor
        }
    }

    private func iconForMetricTab(_ tab: MetricTab) -> String {
        switch tab {
        case .vocab: return "text.bubble.fill"
        case .listening: return "headphones"
        case .speaking: return "waveform"
        @unknown default: return "chart.bar.fill"
        }
    }

    private func matrixTileColor(level: Int, base: Color) -> Color {
        switch level {
        case 0: return Color(uiColor: .tertiarySystemFill).opacity(0.60)
        case 1: return base.opacity(0.32)
        case 2: return base.opacity(0.58)
        case 3: return base.opacity(0.82)
        default: return base
        }
    }
}

// MARK: - Inline Icon-Only Glass Control Bar (Matched Geometry Springs)

private struct InlineIconOnlyGlassBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    @Binding var selection: Item
    let colorProvider: (Item) -> Color
    let iconProvider: (Item) -> String

    @Namespace private var barNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item == selection
                let itemColor = colorProvider(item)

                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        selection = item
                    }
                } label: {
                    ZStack {
                        Image(systemName: iconProvider(item))
                            .font(.system(size: 14, weight: isSelected ? .black : .bold))
                            .foregroundStyle(isSelected ? Color.white : itemColor.opacity(0.85))
                            .symbolEffect(.bounce.byLayer, value: isSelected)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IconBarTapButtonStyle())
                .background {
                    if isSelected {
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(itemColor)
                                .shadow(color: itemColor.opacity(0.45), radius: 8, y: 2)

                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.70), Color.white.opacity(0.15)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.0
                                )
                        }
                        .padding(3)
                        .matchedGeometryEffect(id: "ActiveMetricDroplet", in: barNamespace)
                    }
                }
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        }
    }
}

// MARK: - Button Press Style

private struct IconBarTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.snappy(duration: 0.18, extraBounce: 0.08), value: configuration.isPressed)
    }
}

private struct MetricsSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: configuration.isPressed)
    }
}