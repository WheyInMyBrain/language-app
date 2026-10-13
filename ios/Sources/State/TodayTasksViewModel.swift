
import SwiftUI
import Observation

public struct ConcentricRingItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let current: Double
    public let target: Double
    public let unit: String
    public let color: Color
    public let radius: CGFloat
    public let stroke: CGFloat
    public let pct: Double

    public init(id: String, title: String, icon: String, current: Double, target: Double, unit: String, color: Color, radius: CGFloat, stroke: CGFloat) {
        self.id = id
        self.title = title
        self.icon = icon
        self.current = current
        self.target = target
        self.unit = unit
        self.color = color
        self.radius = radius
        self.stroke = stroke
        self.pct = target > 0 ? min(1.0, current / target) : 0
    }
}

@Observable
@MainActor
public final class TodayTasksViewModel {
    public private(set) var todayStr: String = ""
    public private(set) var todayLog: CalendarEntry? = nil
    public private(set) var manifest: DailyMissionManifest? = nil
    public private(set) var rings: [ConcentricRingItem] = []
    public private(set) var averagePercentage: Int = 0

    public var focusedRingId: String? = nil

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    public init() {}

    public func recompute(
        activeLang: String,
        calendarIndex: [String: CalendarEntry],
        cards: [String: SRSCard]
    ) {
        let today = dateFormatter.string(from: Date())
        self.todayStr = today

        let key = "\(activeLang):\(today)"
        let log = calendarIndex[key]
        self.todayLog = log

        let computedManifest = MomentumEngine.getDailyMissionManifest(
            todayStr: today,
            langCode: activeLang,
            calendarIndex: calendarIndex,
            cards: cards
        )
        self.manifest = computedManifest

        let langContext = ActiveLanguageContext.shared
        let vocabCurrent = Double(log?.word ?? 0)
        let listenCurrent = (log?.listening_time ?? 0) / 60.0
        let speakCurrent = (log?.speaking_time ?? 0) / 60.0
        let ciCurrent = Double(log?.ci ?? 0)
        let grammarCurrent = Double(log?.grammar ?? 0)

        let items: [ConcentricRingItem] = [
            ConcentricRingItem(id: "vocab", title: "Vocabulary", icon: "bubble.left.and.bubble.right.fill", current: vocabCurrent, target: computedManifest.vocabGoal.target, unit: "w", color: langContext.vocabColor, radius: 84, stroke: 8.5),
            ConcentricRingItem(id: "listening", title: "Listening", icon: "headphones", current: listenCurrent, target: computedManifest.listeningGoal.target, unit: "m", color: langContext.listeningColor, radius: 71, stroke: 8.5),
            ConcentricRingItem(id: "speaking", title: "Speaking", icon: "mic.fill", current: speakCurrent, target: computedManifest.speakingGoal.target, unit: "m", color: langContext.speakingColor, radius: 58, stroke: 8.5),
            ConcentricRingItem(id: "ci", title: "CI Video", icon: "play.circle.fill", current: ciCurrent, target: 1.0, unit: "v", color: langContext.themeColor, radius: 45, stroke: 8.5),
            ConcentricRingItem(id: "grammar", title: "Grammar", icon: "character.book.closed.fill", current: grammarCurrent, target: 1.0, unit: "p", color: langContext.grammarColor, radius: 32, stroke: 8.5)
        ]

        self.rings = items
        let sum = items.reduce(0.0) { $0 + $1.pct }
        self.averagePercentage = items.isEmpty ? 0 : Int((sum / Double(items.count) * 100).rounded())
    }
}