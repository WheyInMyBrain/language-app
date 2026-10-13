import SwiftUI

public enum GlyphGridType: Sendable {
    case rice   // 米字格 (Chinese / Japanese Kanji)
    case lined  // Baseline guide (Arabic / Indic)
    case square // Plain bounding box
}

public struct GlyphInspectionLabels: Sendable {
    public let primaryPhonetic: String
    public let component1: String
    public let component2: String
    public let mnemonic: String

    public init(primaryPhonetic: String, component1: String, component2: String, mnemonic: String) {
        self.primaryPhonetic = primaryPhonetic
        self.component1 = component1
        self.component2 = component2
        self.mnemonic = mnemonic
    }
}

public protocol LanguageStrategy: Sendable {
    var code: String { get }
    var name: String { get }
    var isRTL: Bool { get }

    var defaultGoals: LanguageGoals { get }
    var defaultMilestones: LanguageMilestones { get }
    var defaultMomentum: LanguageMomentumConfig { get }
    var defaultColors: LanguageColors { get }
    var defaultTones: [Int: String] { get }

    // Glyph Inspection Strategy
    var gridType: GlyphGridType { get }
    var inspectionLabels: GlyphInspectionLabels { get }
    func isInspectable(character: Character) -> Bool
    func detectInflection(text: String) -> Int

    // High-performance tokenization
    func colorize(primary: String, secondary: String, palette: [Int: Color]) -> TokenizedPhonetics
}

public extension LanguageStrategy {
    var isRTL: Bool { false }
    var defaultGoals: LanguageGoals { LanguageConfigDefaults.goals }
    var defaultMilestones: LanguageMilestones { LanguageConfigDefaults.milestones }
    var defaultMomentum: LanguageMomentumConfig { LanguageConfigDefaults.momentum }
    var defaultColors: LanguageColors { LanguageConfigDefaults.colors }
    var defaultTones: [Int: String] { [:] }
    var gridType: GlyphGridType { .square }
    var inspectionLabels: GlyphInspectionLabels {
        GlyphInspectionLabels(primaryPhonetic: "Phonetic", component1: "Root", component2: "Affix", mnemonic: "Hint")
    }
    func isInspectable(character: Character) -> Bool { false }
    func detectInflection(text: String) -> Int { 5 }
}