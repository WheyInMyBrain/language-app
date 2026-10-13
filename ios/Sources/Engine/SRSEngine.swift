import Foundation

public struct SRSNextState: Sendable, Equatable {
    public let interval: Double
    public let ease: Double
    public let dueDate: String

    public init(interval: Double, ease: Double, dueDate: String) {
        self.interval = interval
        self.ease = ease
        self.dueDate = dueDate
    }
}

public enum SRSEngine {
    private static let calendar: Calendar = {
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

    /// Computes the next SM-2 interval and ease factor
    public static func calculateNextState(
        currentRev: Int,
        currentInterval: Double,
        currentEase: Double,
        grade: SRSGrade,
        todayStr: String
    ) -> SRSNextState {
        var interval: Double
        var ease = currentEase

        switch grade {
        case .again:
            interval = 1.0
            ease = max(1.3, currentEase - 0.20)
        case .hard:
            interval = max(1.0, currentInterval * 1.20)
            ease = max(1.3, currentEase - 0.15)
        case .good:
            if currentRev == 0 {
                interval = 1.0
            } else if currentRev == 1 {
                interval = 6.0
            } else {
                interval = max(1.0, currentInterval * currentEase)
            }
        case .easy:
            if currentRev == 0 {
                interval = 4.0
            } else {
                interval = max(1.0, currentInterval * currentEase * 1.30)
            }
            ease += 0.15
        }

        let daysToAdd = Int(interval.rounded())
        let nextDueDate = addDays(to: todayStr, days: daysToAdd)

        return SRSNextState(interval: interval, ease: ease, dueDate: nextDueDate)
    }

    public static func addDays(to dateStr: String, days: Int) -> String {
        guard let date = isoFormatter.date(from: dateStr),
              let nextDate = calendar.date(byAdding: .day, value: days, to: date) else {
            return dateStr
        }
        return isoFormatter.string(from: nextDate)
    }

    public static func daysBetween(start: String, end: String) -> Int {
        guard let d1 = isoFormatter.date(from: start),
              let d2 = isoFormatter.date(from: end) else {
            return 1
        }
        return max(1, calendar.dateComponents([.day], from: d1, to: d2).day ?? 1)
    }

    public static func intervalPreview(currentInterval: Double, currentEase: Double, grade: SRSGrade) -> String {
        let state = calculateNextState(
            currentRev: 1,
            currentInterval: currentInterval,
            currentEase: currentEase,
            grade: grade,
            todayStr: "2026-01-01"
        )
        let days = Int(state.interval.rounded())
        return days <= 0 ? "1d" : "\(days)d"
    }
}