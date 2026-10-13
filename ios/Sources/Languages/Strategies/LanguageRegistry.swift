import SwiftUI

public enum LanguageRegistry {
    private static let registeredStrategies: [String: any LanguageStrategy] = [
        "zh-CN": ChineseStrategy(),
        "ar": ArabicStrategy()
    ]

    public static func strategy(for code: String) -> any LanguageStrategy {
        if let exact = registeredStrategies[code] {
            return exact
        }
        let prefix = code.components(separatedBy: "-").first ?? code
        if let fallback = registeredStrategies.first(where: { $0.key.starts(with: prefix) })?.value {
            return fallback
        }
        return DefaultStrategy(code: code)
    }
}

// Fallback strategy for arbitrary languages
private struct DefaultStrategy: LanguageStrategy {
    let code: String
    var name: String { code }

    func colorize(primary: String, secondary: String, palette: [Int: Color]) -> TokenizedPhonetics {
        PhoneticsFormatter.tokenize(primary: primary, secondary: secondary)
    }
}