import Foundation
import Observation
import SwiftUI

public enum DaySectionFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case vocab = "Vocab"
    case ci = "CI Video"
    case listening = "Listening"
    case grammar = "Grammar"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "square.stack.3d.up.fill"
        case .vocab: return "text.bubble.fill"
        case .ci: return "play.circle.fill"
        case .listening: return "headphones"
        case .grammar: return "character.book.closed.fill"
        }
    }
}

@Observable
@MainActor
public final class DaySessionViewModel {
    public var activeFilter: DaySectionFilter = .all
    public private(set) var formattedDisplayDate: String = ""

    private static let isoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()

    public init() {}

    public func updateDateDisplay(dateStr: String) {
        if let date = Self.isoFormatter.date(from: dateStr) {
            self.formattedDisplayDate = Self.displayFormatter.string(from: date)
        } else {
            self.formattedDisplayDate = dateStr
        }
    }

    public func calculateOffsetDate(current: String, offsetDays: Int) -> String {
        guard let d = Self.isoFormatter.date(from: current),
              let next = Calendar.current.date(byAdding: .day, value: offsetDays, to: d) else {
            return current
        }
        return Self.isoFormatter.string(from: next)
    }
}