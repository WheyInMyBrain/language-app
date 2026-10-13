import Foundation

// MARK: - Models

public struct AdaptiveGoalResult: Sendable, Equatable {
    public let target: Double
    public let baseline: Double
    public let floor: Double
    public let ceiling: Double
    public let momentum: Double
    public let zone: String // "recovery", "homeostasis", "overdrive"
    public let ratio: Double
    public let history: [Double]
}

public struct RevisionTask: Identifiable, Sendable, Equatable {
    public var id: String { "\(date):\(revision)" }
    public let date: String
    public let revision: Int
    public let statusLabel: String
    public let urgencyCategory: String // "today", "overdue"
    public let overdueDays: Int
    public let priorityScore: Int
}

public struct CatchUpTask: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { "\(date)#\(wordIndex)" }
    public let date: String
    public let wordIndex: Int
}

public struct CatchUpBatch: Sendable, Equatable {
    public let surfaced: [CatchUpTask]
    public let quota: Int
    public let completedCount: Int
    public let hiddenCount: Int
}

public struct TriDeckCounts: Sendable, Equatable {
    public let vision: Int
    public let listen: Int
    public let write: Int
    public var totalDue: Int { vision + listen + write }

    public init(vision: Int = 0, listen: Int = 0, write: Int = 0) {
        self.vision = vision
        self.listen = listen
        self.write = write
    }
}

public struct DailyMissionManifest: Sendable, Equatable {
    public let vocabGoal: AdaptiveGoalResult
    public let listeningGoal: AdaptiveGoalResult
    public let speakingGoal: AdaptiveGoalResult
    public let srs: TriDeckCounts
    public let revisions: [RevisionTask]
    public let unvoiced: CatchUpBatch
}

// MARK: - Native Momentum Engine

public enum MomentumEngine {
    private static let isoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    // MARK: - Core Math (Vectorized EMA)

    public static func calculateAlpha(halfLifeDays: Double = 2.5) -> Double {
        1.0 - exp(-log(2.0) / max(halfLifeDays, 0.5))
    }

    public static func calculateEMA(history: [Double], baseline: Double, alpha: Double = 0.25) -> Double {
        guard !history.isEmpty else { return baseline }
        var ema = history[0]
        for i in 1..<history.count {
            ema = alpha * max(0.0, history[i]) + (1.0 - alpha) * ema
        }
        return ema
    }

    public static func evaluateTargetZone(
        mt: Double,
        baseline: Double,
        floor: Double,
        ceiling: Double
    ) -> (rawTarget: Double, zone: String, ratio: Double) {
        let ratio = baseline > 0 ? (mt / baseline) : 1.0
        var rawTarget = baseline
        var zone = "homeostasis"

        if ratio < 0.60 {
            zone = "recovery"
            rawTarget = max(floor, mt * 1.25)
        } else if ratio > 1.15 {
            zone = "overdrive"
            rawTarget = min(ceiling, baseline * pow(ratio, 0.65))
        } else {
            zone = "homeostasis"
            rawTarget = 0.70 * baseline + 0.30 * mt
        }

        return (rawTarget, zone, ratio)
    }

    // MARK: - Adaptive Goal Evaluation

    public static func getAdaptiveGoal(
        metric: String,
        langCode: String,
        calendarIndex: [String: CalendarEntry]
    ) -> AdaptiveGoalResult {
        let strategy = LanguageRegistry.strategy(for: langCode)
        let momentumCfg = strategy.defaultMomentum

        let config: MetricMomentumConfig
        let isTime: Bool
        let step: Double

        switch metric {
        case "listening":
            config = momentumCfg.listening
            isTime = true
            step = 5.0
        case "speaking":
            config = momentumCfg.speaking
            isTime = true
            step = 5.0
        default: // vocab
            config = momentumCfg.vocab
            isTime = false
            step = 1.0
        }

        let history = get7DayHistory(metric: metric, isTime: isTime, langCode: langCode, calendarIndex: calendarIndex)
        let alpha = calculateAlpha(halfLifeDays: config.halfLifeDays)
        let mt = calculateEMA(history: history, baseline: config.baseline, alpha: alpha)

        let eval = evaluateTargetZone(mt: mt, baseline: config.baseline, floor: config.floor, ceiling: config.ceiling)
        let quantized = (eval.rawTarget / step).rounded() * step
        let finalTarget = max(config.floor, min(config.ceiling, quantized))

        return AdaptiveGoalResult(
            target: finalTarget,
            baseline: config.baseline,
            floor: config.floor,
            ceiling: config.ceiling,
            momentum: (mt * 10).rounded() / 10,
            zone: eval.zone,
            ratio: (eval.ratio * 100).rounded() / 100,
            history: history
        )
    }

    private static func get7DayHistory(
        metric: String,
        isTime: Bool,
        langCode: String,
        calendarIndex: [String: CalendarEntry]
    ) -> [Double] {
        var results: [Double] = []
        results.reserveCapacity(7)
        let today = Date()

        for i in (1...7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let dateStr = isoFormatter.string(from: date)
            let key = "\(langCode):\(dateStr)"

            let entry = calendarIndex[key]
            let val: Double
            if metric == "listening" {
                val = (entry?.listening_time ?? 0) / 60.0
            } else if metric == "speaking" {
                val = (entry?.speaking_time ?? 0) / 60.0
            } else {
                val = Double(entry?.word ?? 0)
            }
            results.append(val.rounded())
        }
        return results
    }

    // MARK: - Daily Mission Manifest Assembly

    public static func getDailyMissionManifest(
        todayStr: String,
        langCode: String,
        calendarIndex: [String: CalendarEntry],
        cards: [String: SRSCard]
    ) -> DailyMissionManifest {
        let vocabGoal = getAdaptiveGoal(metric: "vocab", langCode: langCode, calendarIndex: calendarIndex)
        let listeningGoal = getAdaptiveGoal(metric: "listening", langCode: langCode, calendarIndex: calendarIndex)
        let speakingGoal = getAdaptiveGoal(metric: "speaking", langCode: langCode, calendarIndex: calendarIndex)

        // 1. Uncapped Tri-Deck Counts
        var srsVision = 0
        var srsListen = 0
        var srsWrite = 0

        for card in cards.values {
            let isDue = (card.due_date == nil || (card.due_date ?? "") <= todayStr)
            if isDue {
                switch card.card_type {
                case "listening", "audio":
                    srsListen += 1
                case "writing":
                    srsWrite += 1
                default:
                    srsVision += 1
                }
            }
        }

        // 2. Scheduled Revisions (Lowest Revision First)
        var revisions: [RevisionTask] = []
        let prefix = "\(langCode):"

        let entries = calendarIndex
            .filter { $0.key.hasPrefix(prefix) }
            .map { $0.value }
            .sorted { $0.date > $1.date }

        for entry in entries {
            let rev = Int(entry.revision)
            let dueDate = entry.due_date ?? entry.date
            let date = entry.date

            if rev < 1 {
                if date < todayStr {
                    let diff = SRSEngine.daysBetween(start: date, end: todayStr)
                    revisions.append(RevisionTask(
                        date: date,
                        revision: 0,
                        statusLabel: "+\(diff)d LATE",
                        urgencyCategory: "overdue",
                        overdueDays: diff,
                        priorityScore: -10000 - (diff * 10)
                    ))
                } else if date == todayStr {
                    revisions.append(RevisionTask(
                        date: date,
                        revision: 0,
                        statusLabel: "TODAY",
                        urgencyCategory: "today",
                        overdueDays: 0,
                        priorityScore: -5000
                    ))
                }
            } else if dueDate < todayStr {
                let diff = SRSEngine.daysBetween(start: dueDate, end: todayStr)
                let revWeight = (10 - min(rev, 9)) * 100
                revisions.append(RevisionTask(
                    date: date,
                    revision: rev,
                    statusLabel: "+\(diff)d LATE",
                    urgencyCategory: "overdue",
                    overdueDays: diff,
                    priorityScore: -revWeight - diff
                ))
            } else if dueDate == todayStr {
                revisions.append(RevisionTask(
                    date: date,
                    revision: rev,
                    statusLabel: "TODAY",
                    urgencyCategory: "today",
                    overdueDays: 0,
                    priorityScore: 10 + rev
                ))
            }
        }

        revisions.sort { $0.priorityScore < $1.priorityScore }

        // 3. Catch-Up Audio Siphon
        var voiceQuota = 5
        if speakingGoal.zone == "recovery" || speakingGoal.ratio < 0.60 {
            voiceQuota = 2
        } else if speakingGoal.zone == "overdrive" || speakingGoal.ratio > 1.20 {
            voiceQuota = 8
        }

        var unvoicedBacklog: [CatchUpTask] = []
        let pastEntries = entries.filter { $0.date < todayStr }.sorted { $0.date < $1.date }

        for entry in pastEntries {
            for wIdx in entry.unvoiced_words_indices {
                unvoicedBacklog.append(CatchUpTask(date: entry.date, wordIndex: wIdx))
            }
        }

        let assignedCohort = Array(unvoicedBacklog.prefix(voiceQuota))
        let hiddenCount = max(0, unvoicedBacklog.count - assignedCohort.count)

        return DailyMissionManifest(
            vocabGoal: vocabGoal,
            listeningGoal: listeningGoal,
            speakingGoal: speakingGoal,
            srs: TriDeckCounts(vision: srsVision, listen: srsListen, write: srsWrite),
            revisions: revisions,
            unvoiced: CatchUpBatch(surfaced: assignedCohort, quota: voiceQuota, completedCount: 0, hiddenCount: hiddenCount)
        )
    }
}