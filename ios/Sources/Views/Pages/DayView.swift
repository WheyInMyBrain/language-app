import SwiftUI

public struct DayView: View {
    public let date: String
    public let langCode: String
    public var onSelectDate: (String) -> Void

    @Bindable var dayStore = DaySessionStore.shared
    @State private var viewModel = DaySessionViewModel()
    
    // Scroll tracking to drive adaptive glass compression
    @State private var scrollOffsetY: CGFloat = 0
    @Namespace private var filterTabNamespace

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    public init(date: String, langCode: String, onSelectDate: @escaping (String) -> Void) {
        self.date = date
        self.langCode = langCode
        self.onSelectDate = onSelectDate
    }

    private var ciActivities: [ActivityItem] {
        dayStore.activities.filter { $0.activity_type == .ci }
    }

    private var listeningActivities: [ActivityItem] {
        dayStore.activities.filter { $0.activity_type == .listening }
    }

    private var grammarActivities: [ActivityItem] {
        dayStore.activities.filter { $0.activity_type == .grammar }
    }

    private var totalCount: Int {
        dayStore.words.count + dayStore.activities.count
    }

    private var isAtTop: Bool {
        scrollOffsetY > -30
    }

    private var isScrolledDown: Bool {
        scrollOffsetY < -100
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // MARK: - 1. Scrollable Canvas
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Geometry reader offset tracker
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("DayScrollCoordinateSpace")).minY
                            )
                    }
                    .frame(height: 0)

                    // Top spacer for floating OmniBar
                    Color.clear.frame(height: 70)

                    // Minimal Cockpit Scrubber
                    dateScrubberCockpit

                    // Minimal Filter Glass Bar
                    minimalFilterChipsBar

                    // Content Canvas
                    if !dayStore.isLoaded {
                        loadingCanvasState
                    } else if totalCount == 0 {
                        fluidEmptyCanvasState
                    } else {
                        sectionsCanvas
                    }

                    // Bottom spacer for floating SRS Bar
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .coordinateSpace(name: "DayScrollCoordinateSpace")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffsetY = value
            }

            // MARK: - 2. Top Floating Adaptive OmniBar
            VStack {
                OmniBarView(activeDate: date)
                    .scaleEffect(isAtTop ? 1.0 : 0.95)
                    .opacity(isAtTop ? 1.0 : 0.90)
                    .shadow(color: .black.opacity(isAtTop ? 0.08 : 0.16), radius: 18, y: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isAtTop)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                Spacer()
            }

            // MARK: - 3. Bottom Floating Adaptive SRS Bar
            VStack {
                Spacer()

                SRSBarView(
                    session: dayStore.session,
                    activeDate: date,
                    onReview: { grade in
                        Task {
                            await dayStore.updateSessionSRS(grade: grade, dateStr: date)
                            MetadataStore.shared.recordReview(
                                langCode: langCode,
                                date: date,
                                type: "day_revision"
                            )
                        }
                    }
                )
                .scaleEffect(isScrolledDown ? 1.0 : 0.93)
                .opacity(isScrolledDown ? 1.0 : 0.85)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isScrolledDown)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.formattedDisplayDate)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            dayStore.connect(langCode: langCode, dateStr: date)
            viewModel.updateDateDisplay(dateStr: date)
        }
        .onChange(of: date) { _, newDate in
            dayStore.connect(langCode: langCode, dateStr: newDate)
            viewModel.updateDateDisplay(dateStr: newDate)
        }
    }

    // MARK: - 1. Minimal Date Scrubber Cockpit

    private var dateScrubberCockpit: some View {
        HStack(spacing: 12) {
            // Previous Date
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelectDate(viewModel.calculateOffsetDate(current: date, offsetDays: -1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill).opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(DayButtonSquishStyle())

            // Date Telemetry Display
            VStack(spacing: 2) {
                Text(viewModel.formattedDisplayDate)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(date)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(lang.themeColor)
            }
            .frame(maxWidth: .infinity)

            // Next Date
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelectDate(viewModel.calculateOffsetDate(current: date, offsetDays: 1))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill).opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(DayButtonSquishStyle())

            // Live Activity Aura Pill
            HStack(spacing: 5) {
                Circle().fill(lang.vocabColor).frame(width: 6, height: 6)
                    .opacity(dayStore.words.isEmpty ? 0.2 : 1.0)
                Circle().fill(lang.themeColor).frame(width: 6, height: 6)
                    .opacity(ciActivities.isEmpty ? 0.2 : 1.0)
                Circle().fill(lang.listeningColor).frame(width: 6, height: 6)
                    .opacity(listeningActivities.isEmpty ? 0.2 : 1.0)
                Circle().fill(lang.grammarColor).frame(width: 6, height: 6)
                    .opacity(grammarActivities.isEmpty ? 0.2 : 1.0)

                Text("\(totalCount)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.5))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.85))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    // MARK: - 2. Minimal Filter Chips Bar (Icons & Counts Only)

    private var minimalFilterChipsBar: some View {
        HStack(spacing: 6) {
            ForEach(DaySectionFilter.allCases) { filter in
                let isSelected = viewModel.activeFilter == filter
                let activeColor = filterColor(for: filter)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        viewModel.activeFilter = filter
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 11, weight: isSelected ? .black : .bold))

                        Text("\(count(for: filter))")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSelected ? Color.white : activeColor)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(activeColor)
                                .shadow(color: activeColor.opacity(0.4), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "ActiveDayFilterPill", in: filterTabNamespace)
                        } else {
                            Capsule()
                                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.35))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.70))
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        )
    }

    private func count(for filter: DaySectionFilter) -> Int {
        switch filter {
        case .all: return totalCount
        case .vocab: return dayStore.words.count
        case .ci: return ciActivities.count
        case .listening: return listeningActivities.count
        case .grammar: return grammarActivities.count
        }
    }

    private func filterColor(for filter: DaySectionFilter) -> Color {
        switch filter {
        case .all: return lang.themeColor
        case .vocab: return lang.vocabColor
        case .ci: return lang.themeColor
        case .listening: return lang.listeningColor
        case .grammar: return lang.grammarColor
        }
    }

    // MARK: - 3. Content Sections

    private var sectionsCanvas: some View {
        VStack(spacing: 24) {
            if viewModel.activeFilter == .all || viewModel.activeFilter == .vocab {
                vocabSection
            }
            if viewModel.activeFilter == .all || viewModel.activeFilter == .ci {
                ciSection
            }
            if viewModel.activeFilter == .all || viewModel.activeFilter == .listening {
                listeningSection
            }
            if viewModel.activeFilter == .all || viewModel.activeFilter == .grammar {
                grammarSection
            }
        }
    }

    private var vocabSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            minimalSectionHeader(
                icon: "text.bubble.fill",
                color: lang.vocabColor,
                count: dayStore.words.count
            )

            if dayStore.words.isEmpty {
                emptyRowPlaceholder(color: lang.vocabColor)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    ForEach(Array(dayStore.words.enumerated()), id: \.element.id) { _, word in
                        OmniCardView(
                            content: .vocab(word),
                            index: word.word_index,
                            date: date
                        )
                    }
                }
            }
        }
    }

    private var ciSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            minimalSectionHeader(
                icon: "play.circle.fill",
                color: lang.themeColor,
                count: ciActivities.count
            )

            if ciActivities.isEmpty {
                emptyRowPlaceholder(color: lang.themeColor)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(ciActivities.enumerated()), id: \.element.id) { _, item in
                        OmniCardView(
                            content: .ci(item),
                            index: item.item_index,
                            date: date
                        )
                    }
                }
            }
        }
    }

    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            minimalSectionHeader(
                icon: "headphones",
                color: lang.listeningColor,
                count: listeningActivities.count
            )

            if listeningActivities.isEmpty {
                emptyRowPlaceholder(color: lang.listeningColor)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(listeningActivities.enumerated()), id: \.element.id) { _, item in
                        OmniCardView(
                            content: .listening(item),
                            index: item.item_index,
                            date: date
                        )
                    }
                }
            }
        }
    }

    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            minimalSectionHeader(
                icon: "character.book.closed.fill",
                color: lang.grammarColor,
                count: grammarActivities.count
            )

            if grammarActivities.isEmpty {
                emptyRowPlaceholder(color: lang.grammarColor)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(grammarActivities.enumerated()), id: \.element.id) { _, item in
                        OmniCardView(
                            content: .grammar(item),
                            index: item.item_index,
                            date: date
                        )
                    }
                }
            }
        }
    }

    // MARK: - Minimal Stage Rule

    private func minimalSectionHeader(icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, color.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(color)

                Text("\(count)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.5))
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
        .padding(.vertical, 4)
    }

    private func emptyRowPlaceholder(color: Color) -> some View {
        HStack {
            Spacer()
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 6, height: 6)
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.25))
        }
    }

    // MARK: - Living Fluid Empty State

    private var fluidEmptyCanvasState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(lang.themeColor.opacity(0.14))
                    .frame(width: 52, height: 52)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(lang.themeColor)
            }

            VStack(spacing: 3) {
                Text("Canvas Ready")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Log items via Omnibar to illuminate this day.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.70))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), lang.themeColor.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var loadingCanvasState: some View {
        ProgressView()
            .padding(40)
    }
}

// MARK: - Button Press Style

private struct DayButtonSquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.snappy(duration: 0.18, extraBounce: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Scroll Offset Preference Key
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}