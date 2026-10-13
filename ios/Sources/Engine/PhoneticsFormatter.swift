import SwiftUI

public struct PhoneticToken: Identifiable, Sendable {
    public var id: String { text + (color?.description ?? "") }
    public let text: String
    public let color: Color?
    public let chars: [String]?

    public init(text: String, color: Color? = nil, chars: [String]? = nil) {
        self.text = text
        self.color = color
        self.chars = chars
    }
}

public struct TokenizedPhonetics: Sendable {
    public let primaryTokens: [PhoneticToken]
    public let secondaryTokens: [PhoneticToken]

    public init(primaryTokens: [PhoneticToken], secondaryTokens: [PhoneticToken]) {
        self.primaryTokens = primaryTokens
        self.secondaryTokens = secondaryTokens
    }
}

public enum PhoneticsFormatter {
    /// Removes tone marks, accents, and diacritics (e.g., "xuéxí" -> "xuexi", "lǜ" -> "lv")
    public static func stripDiacritics(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        let folded = input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ü", with: "v", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return folded
    }

    /// Basic tokenizer fallback (can be overridden by language configurations)
    public static func tokenize(primary: String, secondary: String) -> TokenizedPhonetics {
        let pTokens = [PhoneticToken(text: primary)]
        let sTokens = [PhoneticToken(text: secondary)]
        return TokenizedPhonetics(primaryTokens: pTokens, secondaryTokens: sTokens)
    }
}