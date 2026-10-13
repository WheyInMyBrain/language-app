import Foundation
import Observation
import SwiftUI

public enum MetricTab: String, CaseIterable, Identifiable, Sendable {
    case vocab = "Vocab"
    case listening = "Listen"
    case speaking = "Speak"

    public var id: String { rawValue }
}

public struct TrajectoryPoint: Identifiable, Sendable, Equatable {
    public var id: String { dateStr }
    public let date: Date
    public let dateStr: String
    public let value: Double
}

public struct HeatmapDay: Identifiable, Sendable, Equatable {
    public var id: String { date }
    public let date: String
    public let level: Int
    public let label: String
}

public struct MilestoneData: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let color: Color
    public let pct: Double
    public let badge: String
    public let pace: String
    public let est: String
    public let goalLabel: String
}

public struct AggregatesSummary: Sendable, Equatable {
    public let streak: Int
    public let vocab: Int
    public let grammar: Int
    public let ci: Int
    public let listenSec: Double
    public let speakSec: Double
}

@Observable
@MainActor
public final class DashboardMetricsViewModel {
    public var activeChartTab: MetricTab = .vocab {
        didSet { updateChartAndHeatmap() }
    }
    public var activeHeatmapTab: MetricTab = .vocab {
        didSet { updateHeatmapOnly() }
    }
    
    public var selectedChartDate: Date? = nil
    public var inspectedDay: HeatmapDay? = nil

    public private(set) var aggregates = AggregatesSummary(streak: 0, vocab: 0, grammar: 0, ci: 0, listenSec: 0, speakSec: 0)
    public private(set) var milestones: [MilestoneData] = []
    public private(set) var chartPoints: [TrajectoryPoint] = []
    public private(set) var heatmapWeeks: [[HeatmapDay]] = []
    
    public private(set) var chartAccentColor: Color = .green
    public private(set) var heatmapAccentColor: Color = .green

    // Cached sorted entries to prevent redundant re-sorting on tab changes
    private var cachedSortedEntries: [CalendarEntry] = []
    private var activeLanguageCode: String = ""

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private static let isoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    public init() {}

    public func sync(activeLang: String, calendarIndex: [String: CalendarEntry], streak: Int) {
        self.activeLanguageCode = activeLang
        let prefix = "\(activeLang):"

        // Single-pass extraction & ascending chronological sort
        self.cachedSortedEntries = calendarIndex
            .lazy
            .filter { $0.key.hasPrefix(prefix) }
            .map { $0.value }
            .sorted { $0.date < $1.date }

        recomputeAll(streak: streak, calendarIndex: calendarIndex)
    }

    private func recomputeAll(streak: Int, calendarIndex: [String: CalendarEntry]) {
        let langContext = ActiveLanguageContext.shared
        let entries = cachedSortedEntries

        // 1. Aggregates (O(N) single loop)
        var v = 0, g = 0, c = 0, l = 0.0, s = 0.0
        var vocabDailies: [Double] = []
        var listenDailies: [Double] = []
        var speakDailies: [Double] = []
        vocabDailies.reserveCapacity(entries.count)
        listenDailies.reserveCapacity(entries.count)
        speakDailies.reserveCapacity(entries.count)

        for entry in entries {
            v += entry.word
            g += entry.grammar
            c += entry.ci
            l += entry.listening_time
            s += entry.speaking_time

            if entry.word > 0 { vocabDailies.append(Double(entry.word)) }
            if entry.listening_time > 0 { listenDailies.append(entry.listening_time) }
            if entry.speaking_time > 0 { speakDailies.append(entry.speaking_time) }
        }

        self.aggregates = AggregatesSummary(
            streak: streak,
            vocab: v,
            grammar: g,
            ci: c,
            listenSec: l,
            speakSec: s
        )

        // 2. Milestones with ETA
        let strategy = langContext.strategy
        let vTarget = Double(strategy.defaultMilestones.vocab_total)
        let lTarget = strategy.defaultMilestones.listening_hours * 3600.0
        let sTarget = strategy.defaultMilestones.speaking_hours * 3600.0

        let vETA = StatsHelper.calculateETA(current: Double(v), target: vTarget, dailyRate: StatsHelper.calculateMedian(vocabDailies), isTime: false)
        let lETA = StatsHelper.calculateETA(current: l, target: lTarget, dailyRate: StatsHelper.calculateMedian(listenDailies), isTime: true)
        let sETA = StatsHelper.calculateETA(current: s, target: sTarget, dailyRate: StatsHelper.calculateMedian(speakDailies), isTime: true)

        self.milestones = [
            MilestoneData(id: "vocab", title: "Vocabulary Acquisition", icon: "book.fill", color: langContext.vocabColor, pct: min(1.0, Double(v) / vTarget), badge: vETA.badge, pace: vETA.pace, est: vETA.est, goalLabel: "\(Int(vTarget)) words"),
            MilestoneData(id: "listening", title: "Immersion Audio", icon: "headphones", color: langContext.listeningColor, pct: min(1.0, l / lTarget), badge: lETA.badge, pace: lETA.pace, est: lETA.est, goalLabel: "\(Int(strategy.defaultMilestones.listening_hours))h logged"),
            MilestoneData(id: "speaking", title: "Speaking Production", icon: "mic.fill", color: langContext.speakingColor, pct: min(1.0, s / sTarget), badge: sETA.badge, pace: sETA.pace, est: sETA.est, goalLabel: "\(Int(strategy.defaultMilestones.speaking_hours))h logged")
        ]

        updateChartAndHeatmap(calendarIndex: calendarIndex)
    }

    private func updateChartAndHeatmap(calendarIndex: [String: CalendarEntry]? = nil) {
        let langContext = ActiveLanguageContext.shared
        self.chartAccentColor = resolveColor(for: activeChartTab, context: langContext)
        self.heatmapAccentColor = resolveColor(for: activeHeatmapTab, context: langContext)

        // 3. Trajectory Points (Reuses pre-sorted array)
        var running = 0.0
        var pts: [TrajectoryPoint] = []
        pts.reserveCapacity(cachedSortedEntries.count)

        for entry in cachedSortedEntries {
            switch activeChartTab {
            case .vocab: running += Double(entry.word)
            case .listening: running += entry.listening_time / 3600.0
            case .speaking: running += entry.speaking_time / 3600.0
            }
            if let date = Self.isoFormatter.date(from: entry.date) {
                pts.append(TrajectoryPoint(date: date, dateStr: entry.date, value: running))
            }
        }
        self.chartPoints = pts

        updateHeatmapOnly(calendarIndex: calendarIndex)
    }

    private func updateHeatmapOnly(calendarIndex: [String: CalendarEntry]? = nil) {
        let langContext = ActiveLanguageContext.shared
        self.heatmapAccentColor = resolveColor(for: activeHeatmapTab, context: langContext)

        let cal = Self.utcCalendar
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(13 * 7 - 1), to: today) else { return }

        let index = calendarIndex ?? MetadataStore.shared.calendarIndex
        let strategy = langContext.strategy
        let goals = strategy.defaultGoals
        let vGoal = Double(goals.vocab)
        let lGoalSec = Double(goals.listening_minutes * 60)
        let sGoalSec = Double(goals.speaking_minutes * 60)

        var weeks: [[HeatmapDay]] = []
        weeks.reserveCapacity(13)

        for w in 0..<13 {
            var days: [HeatmapDay] = []
            days.reserveCapacity(7)
            for d in 0..<7 {
                if let cur = cal.date(byAdding: .day, value: w * 7 + d, to: start) {
                    let dateStr = Self.isoFormatter.string(from: cur)
                    let entry = index["\(activeLanguageCode):\(dateStr)"]

                    let count = entry?.word ?? 0
                    let lSec = entry?.listening_time ?? 0
                    let sSec = entry?.speaking_time ?? 0

                    let level: Int
                    let label: String

                    switch activeHeatmapTab {
                    case .vocab:
                        level = tier(val: Double(count), target: vGoal)
                        label = "\(count)/\(Int(vGoal)) words"
                    case .listening:
                        level = tier(val: lSec, target: lGoalSec)
                        label = "\(Int(lSec / 60))m/\(goals.listening_minutes)m audio"
                    case .speaking:
                        level = tier(val: sSec, target: sGoalSec)
                        label = "\(Int(sSec / 60))m/\(goals.speaking_minutes)m speech"
                    }
                    days.append(HeatmapDay(date: dateStr, level: level, label: label))
                }
            }
            weeks.append(days)
        }
        self.heatmapWeeks = weeks
    }

    private func resolveColor(for tab: MetricTab, context: ActiveLanguageContext) -> Color {
        switch tab {
        case .vocab: return context.vocabColor
        case .listening: return context.listeningColor
        case .speaking: return context.speakingColor
        }
    }

    private func tier(val: Double, target: Double) -> Int {
        if val <= 0 { return 0 }
        if val >= target { return 4 }
        if val >= target * 0.75 { return 3 }
        if val >= target * 0.50 { return 2 }
        return 1
    }
}