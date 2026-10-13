import SwiftUI

// MARK: - 1. High-Performance Color Representation (32-Bit RGBA)

public struct ColorShades: Codable, Equatable, Sendable {
    public var dark: UInt32
    public var light: UInt32
    public var primary: UInt32

    public init(dark: String? = nil, light: String? = nil, primary: String) {
        let p = Self.parseHex(primary)
        self.primary = p
        self.dark = dark != nil ? Self.parseHex(dark!) : p
        self.light = light != nil ? Self.parseHex(light!) : p
    }

    public var swiftUIColor: Color { Self.toColor(primary) }
    public var darkColor: Color { Self.toColor(dark) }
    public var lightColor: Color { Self.toColor(light) }

    private static func parseHex(_ hex: String) -> UInt32 {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        if clean.count == 6 {
            return UInt32((int << 8) | 0xFF)
        }
        return UInt32(int)
    }

    private static func toColor(_ rgba: UInt32) -> Color {
        let r = Double((rgba >> 24) & 0xFF) / 255.0
        let g = Double((rgba >> 16) & 0xFF) / 255.0
        let b = Double((rgba >> 8) & 0xFF) / 255.0
        let a = Double(rgba & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

public struct LanguageColors: Codable, Equatable, Sendable {
    public var theme: ColorShades?
    public var streak: ColorShades?
    public var vocab: ColorShades?
    public var ci: ColorShades?
    public var listening: ColorShades?
    public var speaking: ColorShades?
    public var grammar: ColorShades?
    public var flashcard: ColorShades?

    public init(
        theme: ColorShades? = nil,
        streak: ColorShades? = nil,
        vocab: ColorShades? = nil,
        ci: ColorShades? = nil,
        listening: ColorShades? = nil,
        speaking: ColorShades? = nil,
        grammar: ColorShades? = nil,
        flashcard: ColorShades? = nil
    ) {
        self.theme = theme
        self.streak = streak
        self.vocab = vocab
        self.ci = ci
        self.listening = listening
        self.speaking = speaking
        self.grammar = grammar
        self.flashcard = flashcard
    }
}

// MARK: - 2. Goals & Milestones

public struct LanguageGoals: Codable, Equatable, Sendable {
    public var vocab: Int
    public var grammar: Int
    public var ci: Int
    public var listening_minutes: Int
    public var speaking_minutes: Int

    public init(vocab: Int = 10, grammar: Int = 1, ci: Int = 1, listening: Int = 45, speaking: Int = 10) {
        self.vocab = vocab
        self.grammar = grammar
        self.ci = ci
        self.listening_minutes = listening
        self.speaking_minutes = speaking
    }
}

public struct LanguageMilestones: Codable, Equatable, Sendable {
    public var vocab_total: Int
    public var listening_hours: Double
    public var speaking_hours: Double

    public init(vocab: Int = 1000, listening: Double = 48, speaking: Double = 12) {
        self.vocab_total = vocab
        self.listening_hours = listening
        self.speaking_hours = speaking
    }
}

// MARK: - 3. Momentum Curves

public struct MetricMomentumConfig: Codable, Equatable, Sendable {
    public var floor: Double
    public var baseline: Double
    public var ceiling: Double
    public var halfLifeDays: Double
    public var maxSlewRate: Double

    public init(floor: Double, baseline: Double, ceiling: Double, halfLife: Double = 2.5, slewRate: Double = 2) {
        self.floor = floor
        self.baseline = baseline
        self.ceiling = ceiling
        self.halfLifeDays = halfLife
        self.maxSlewRate = slewRate
    }
}

public struct SRSPacingConfig: Codable, Equatable, Sendable {
    public var vision: MetricMomentumConfig
    public var listen: MetricMomentumConfig
    public var write: MetricMomentumConfig

    public init(vision: MetricMomentumConfig, listen: MetricMomentumConfig, write: MetricMomentumConfig) {
        self.vision = vision
        self.listen = listen
        self.write = write
    }
}

public struct LanguageMomentumConfig: Codable, Equatable, Sendable {
    public var listening: MetricMomentumConfig
    public var speaking: MetricMomentumConfig
    public var vocab: MetricMomentumConfig
    public var srs: SRSPacingConfig
    public var revisions: MetricMomentumConfig

    public init(
        listening: MetricMomentumConfig,
        speaking: MetricMomentumConfig,
        vocab: MetricMomentumConfig,
        srs: SRSPacingConfig,
        revisions: MetricMomentumConfig
    ) {
        self.listening = listening
        self.speaking = speaking
        self.vocab = vocab
        self.srs = srs
        self.revisions = revisions
    }
}

// MARK: - 4. Language Config & User Overrides

public struct LanguageConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String { code }
    public var code: String
    public var name: String
    public var current_streak: Int = 0
    public var longest_streak: Int = 0
    public var total_days: Int = 0

    public var goals: LanguageGoals?
    public var milestones: LanguageMilestones?
    public var momentum: LanguageMomentumConfig?
    public var colors: LanguageColors?
    public var tones: [Int: String]?

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

// MARK: - 5. Fast Calendar Index & SRS

public enum SRSCardType: UInt8, Codable, Sendable, CaseIterable {
    case visual = 0
    case listening = 1
    case writing = 2

    public var identifier: String {
        switch self {
        case .visual: return "visual"
        case .listening: return "listening"
        case .writing: return "writing"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawInt = try? container.decode(UInt8.self), let val = SRSCardType(rawValue: rawInt) {
            self = val
            return
        }
        let str = try container.decode(String.self)
        switch str {
        case "listening", "audio": self = .listening
        case "writing": self = .writing
        default: self = .visual
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}

public enum SRSGrade: UInt8, Codable, Sendable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3
}

public struct SRSCard: Codable, Identifiable, Equatable, Sendable {
    public var id: String { key ?? "" }
    public var key: String?
    public var card_type: String? // String-backed for wire compatibility with existing stores
    public var due_date: String?
    public var interval: Double = 0
    public var ease: Double = 2.5
    public var reps: Int = 0
    public var lapses: Int = 0
    public var last_reviewed: String?

    public var native_script: String?
    public var pronunciation: String?
    public var translation: String?
    public var link: String?

    public init(key: String? = nil, card_type: String? = "visual") {
        self.key = key
        self.card_type = card_type
    }
}

public struct ReviewCounts: Codable, Equatable, Sendable {
    public var srs_vision: Int = 0
    public var srs_listen: Int = 0
    public var srs_write: Int = 0
    public var day_revisions: Int = 0

    public init() {}
}

public struct CalendarEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String { date }
    public var date: String
    public var revision: Int = 0
    public var due_date: String?

    public var word: Int = 0
    public var ci: Int = 0
    public var grammar: Int = 0
    public var listening: Int = 0

    public var speaking_time: Double = 0
    public var listening_time: Double = 0

    public var vocab_done: Bool = false
    public var ci_done: Bool = false
    public var listening_done: Bool = false
    public var speaking_done: Bool = false
    public var grammar_done: Bool = false

    public var unvoiced_words_indices: [Int] = []
    public var reviews_completed: ReviewCounts = ReviewCounts()

    public init(date: String) {
        self.date = date
    }
}