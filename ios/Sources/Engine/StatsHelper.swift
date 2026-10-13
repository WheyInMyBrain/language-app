import Foundation

public enum StatsHelper {
    public static func formatHoursMins(seconds: Double) -> String {
        let totalMins = Int(seconds / 60)
        let hours = totalMins / 60
        let mins = totalMins % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    public static func calculateMedian(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
        return sorted[count / 2]
    }

    public struct ETAResult: Sendable {
        public let badge: String
        public let pace: String
        public let est: String
    }

    public static func calculateETA(current: Double, target: Double, dailyRate: Double, isTime: Bool) -> ETAResult {
        guard current < target else {
            return ETAResult(badge: "COMPLETED", pace: "Done", est: "Achieved")
        }
        guard dailyRate > 0 else {
            return ETAResult(badge: "PENDING", pace: "0/d", est: "No pace logged")
        }

        let remaining = target - current
        let daysLeft = Int(ceil(remaining / dailyRate))

        let paceStr = isTime ? "\(Int(round(dailyRate / 60)))m/d" : "\(Int(round(dailyRate)))/d"
        let badgeStr = "\(daysLeft)d LEFT"

        let calendar = Calendar.current
        if let targetDate = calendar.date(byAdding: .day, value: daysLeft, to: Date()) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return ETAResult(badge: badgeStr, pace: paceStr, est: formatter.string(from: targetDate))
        }

        return ETAResult(badge: badgeStr, pace: paceStr, est: "in \(daysLeft) days")
    }
}