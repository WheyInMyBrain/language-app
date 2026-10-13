import SwiftUI

public struct ChineseStrategy: LanguageStrategy {
    public let code = "zh-CN"
    public let name = "Chinese"
    public let gridType: GlyphGridType = .rice

    public let inspectionLabels = GlyphInspectionLabels(
        primaryPhonetic: "Pinyin",
        component1: "Radical",
        component2: "Decomposition",
        mnemonic: "Mnemonic Hint"
    )

    public var defaultTones: [Int: String] = [
        1: "#38bdf8", // Tone 1: High flat (Cyan)
        2: "#34d399", // Tone 2: Rising (Emerald)
        3: "#fbbf24", // Tone 3: Dipping (Amber)
        4: "#f87171", // Tone 4: Falling (Coral)
        5: "#94a3b8"  // Tone 5: Neutral (Slate)
    ]

    private static let toneTable: [Character: Int] = [
        "ā": 1, "ē": 1, "ī": 1, "ō": 1, "ū": 1, "ǖ": 1, "Ā": 1, "Ē": 1, "Ī": 1, "Ō": 1, "Ū": 1, "Ǖ": 1,
        "á": 2, "é": 2, "í": 2, "ó": 2, "ú": 2, "ǘ": 2, "Á": 2, "É": 2, "Í": 2, "Ó": 2, "Ú": 2, "Ǘ": 2,
        "ǎ": 3, "ě": 3, "ǐ": 3, "ǒ": 3, "ǔ": 3, "ǚ": 3, "Ǎ": 3, "Ě": 3, "Ǐ": 3, "Ǒ": 3, "Ǚ": 3,
        "à": 4, "è": 4, "ì": 4, "ò": 4, "ù": 4, "ǜ": 4, "À": 4, "È": 4, "Ì": 4, "Ò": 4, "Ù": 4, "Ǜ": 4
    ]

    public init() {}

    public func isInspectable(character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x4E00...0x9FA5).contains(scalar.value)
    }

    public func detectInflection(text: String) -> Int {
        for char in text {
            if let tone = Self.toneTable[char] {
                return tone
            }
        }
        return 5
    }

    public func colorize(primary: String, secondary: String, palette: [Int: Color]) -> TokenizedPhonetics {
        let syllables = secondary.split(whereSeparator: \.isWhitespace).map(String.init)
        let secondaryTokens = syllables.map { s in
            let tone = detectInflection(text: s)
            return PhoneticToken(text: s, color: palette[tone] ?? palette[5])
        }

        let chars = primary.filter { !$0.isWhitespace }
        let primaryTokens: [PhoneticToken]
        if chars.count == syllables.count {
            primaryTokens = zip(chars, syllables).map { char, syll in
                let tone = detectInflection(text: syll)
                return PhoneticToken(text: String(char), color: palette[tone] ?? palette[5])
            }
        } else {
            primaryTokens = chars.map { char in
                PhoneticToken(text: String(char), color: palette[5])
            }
        }

        return TokenizedPhonetics(primaryTokens: primaryTokens, secondaryTokens: secondaryTokens)
    }
}