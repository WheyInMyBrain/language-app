import SwiftUI

public struct DayListView: View {
    public let langCode: String

    @Bindable private var metadata = MetadataStore.shared
    @State private var searchText: String = ""

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private var todayStr: String {
        Self.isoFormatter.string(from: Date())
    }

    private var allDates: [String] {
        var dates: [String] = []
        let cal = Calendar.current
        for offset in 0..<60 {
            if let d = cal.date(byAdding: .day, value: -offset, to: Date()) {
                dates.append(Self.isoFormatter.string(from: d))
            }
        }
        return dates
    }

    private var filteredDates: [String] {
        if searchText.isEmpty {
            return allDates
        }
        return allDates.filter { $0.contains(searchText) }
    }

    public init(langCode: String) {
        self.langCode = langCode
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // MARK: - 1. Search Glass Capsule
                searchGlassBar

                // MARK: - 2. Today Hero Workspace Card
                if searchText.isEmpty || todayStr.contains(searchText) {
                    todayHeroCard
                }

                // MARK: - 3. Timeline Stream Header
                timelineDivider

                // MARK: - 4. Historical Days Stream
                LazyVStack(spacing: 10) {
                    ForEach(filteredDates.filter { $0 != todayStr }, id: \.self) { dateStr in
                        NavigationLink(value: dateStr) {
                            historyDayCard(dateStr: dateStr)
                        }
                        .buttonStyle(DayCardPressStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 1. Search Glass Capsule

    private var searchGlassBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(searchText.isEmpty ? Color.secondary : lang.themeColor)

            TextField("Filter dates (YYYY-MM-DD)...", text: $searchText)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    searchText.isEmpty
                        ? Color.white.opacity(0.15)
                        : lang.themeColor.opacity(0.4),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 2. Today Hero Workspace Card

    private var todayHeroCard: some View {
        NavigationLink(value: todayStr) {
            HStack(spacing: 14) {
                // Date Hologram Box
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [lang.themeColor, lang.themeColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: lang.themeColor.opacity(0.4), radius: 8, y: 3)

                    VStack(spacing: 0) {
                        Text(monthAbbrev(dateStr: todayStr))
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(dayNumber(dateStr: todayStr))
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                // Center Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Today's Session")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)

                        // Pulsing Live Dot
                        Circle()
                            .fill(lang.themeColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: lang.themeColor, radius: 4)
                    }

                    Text(displayTitle(dateStr: todayStr, isToday: true))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Launch Indicator
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(lang.themeColor)
            }
            .padding(14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.95))

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(lang.themeColor.opacity(0.08))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.8), location: 0.0),
                                .init(color: lang.themeColor.opacity(0.5), location: 0.35),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: lang.themeColor.opacity(0.16), radius: 16, y: 6)
        }
        .buttonStyle(DayCardPressStyle())
    }

    // MARK: - 3. Timeline Stream Divider

    private var timelineDivider: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.primary.opacity(0.12)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("ARCHIVE")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.40))
            .clipShape(Capsule())

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.12), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    // MARK: - 4. History Day Card

    private func historyDayCard(dateStr: String) -> some View {
        let entry = metadata.calendarIndex["\(langCode):\(dateStr)"]
        let hasVocab = (entry?.word ?? 0) > 0
        let hasCI = (entry?.ci ?? 0) > 0
        let hasListening = (entry?.listening_time ?? 0) > 0

        return HStack(spacing: 14) {
            // Calendar Pill
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
                    .frame(width: 44, height: 44)

                VStack(spacing: 0) {
                    Text(monthAbbrev(dateStr: dateStr))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(dayNumber(dateStr: dateStr))
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            // Date Text
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(dateStr: dateStr, isToday: false))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(dateStr)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Activity Indicators
            HStack(spacing: 5) {
                if hasVocab {
                    Circle()
                        .fill(lang.vocabColor)
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: lang.vocabColor.opacity(0.6), radius: 2)
                }
                if hasCI {
                    Circle()
                        .fill(lang.themeColor)
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: lang.themeColor.opacity(0.6), radius: 2)
                }
                if hasListening {
                    Circle()
                        .fill(lang.listeningColor)
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: lang.listeningColor.opacity(0.6), radius: 2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.70))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }

    private func monthAbbrev(dateStr: String) -> String {
        guard let d = Self.isoFormatter.date(from: dateStr) else { return "DAY" }
        return Self.monthFormatter.string(from: d).uppercased()
    }

    private func dayNumber(dateStr: String) -> String {
        String(dateStr.suffix(2))
    }

    private func displayTitle(dateStr: String, isToday: Bool) -> String {
        if isToday {
            guard let d = Self.isoFormatter.date(from: dateStr) else { return "Today" }
            return Self.displayDateFormatter.string(from: d)
        }
        guard let d = Self.isoFormatter.date(from: dateStr) else { return dateStr }
        return Self.displayDateFormatter.string(from: d)
    }
}

// MARK: - Native Tactile Card Press Style

private struct DayCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.2, extraBounce: 0.05), value: configuration.isPressed)
    }
}