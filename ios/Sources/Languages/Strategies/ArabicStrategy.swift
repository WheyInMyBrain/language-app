import SwiftUI

public struct ArabicStrategy: LanguageStrategy {
    public let code = "ar"
    public let name = "Arabic"
    public let isRTL = true
    public let gridType: GlyphGridType = .lined

    public let inspectionLabels = GlyphInspectionLabels(
        primaryPhonetic: "Transliteration",
        component1: "Root (Jadhar)",
        component2: "Pattern (Wazn)",
        mnemonic: "Root Meaning"
    )

    public var defaultColors: LanguageColors {
        var base = LanguageConfigDefaults.colors
        base.theme = ColorShades(dark: "#38bdf8", light: "#0284c7", primary: "#0ea5e9")
        base.grammar = ColorShades(dark: "#2dd4bf", light: "#0f766e", primary: "#14b8a6")
        return base
    }

    public var defaultTones: [Int: String] = [
        1: "#38bdf8", // Fatḥah (a) - Cyan
        2: "#f59e0b", // Ḍammah (u) - Amber
        3: "#10b981", // Kasrah (i) - Emerald
        4: "#a855f7", // Sukūn / Shaddah - Purple
        5: "#94a3b8"  // Plain consonant - Slate
    ]

    public init() {}

    public func isInspectable(character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x0600...0x06FF).contains(scalar.value)
    }

    public func detectInflection(text: String) -> Int {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064E, 0x064B: return 1 // Fatḥah, Tanwīn Fatḥ
            case 0x064F, 0x064C: return 2 // Ḍammah, Tanwīn Ḍamm
            case 0x0650, 0x064D: return 3 // Kasrah, Tanwīn Kasr
            case 0x0651, 0x0652: return 4 // Shaddah, Sukūn
            default: continue
            }
        }
        return 5
    }

    public func colorize(primary: String, secondary: String, palette: [Int: Color]) -> TokenizedPhonetics {
        // Arabic primary tokens: keep word units intact to avoid breaking ligatures
        let words = primary.split(whereSeparator: \.isWhitespace).map(String.init)
        let primaryTokens = words.map { word -> PhoneticToken in
            let haraka = detectInflection(text: word)
            return PhoneticToken(
                text: word,
                color: haraka != 5 ? (palette[haraka] ?? palette[5]) : nil
            )
        }

        let secondaryWords = secondary.split(whereSeparator: \.isWhitespace).map(String.init)
        let secondaryTokens = secondaryWords.map {
            PhoneticToken(text: $0, color: nil)
        }

        return TokenizedPhonetics(primaryTokens: primaryTokens, secondaryTokens: secondaryTokens)
    }
}