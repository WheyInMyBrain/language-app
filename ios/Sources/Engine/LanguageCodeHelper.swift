import Foundation

public enum LanguageCodeHelper {
    private static let commonLanguageMap: [String: String] = [
        "chinese": "zh-CN",
        "mandarin": "zh-CN",
        "arabic": "ar",
        "japanese": "ja",
        "korean": "ko",
        "spanish": "es",
        "french": "fr",
        "german": "de",
        "italian": "it",
        "portuguese": "pt",
        "russian": "ru",
        "hindi": "hi",
        "turkish": "tr",
        "dutch": "nl",
        "swedish": "sv",
        "polish": "pl",
        "vietnamese": "vi",
        "thai": "th",
        "greek": "el",
        "hebrew": "he",
        "latin": "la"
    ]

    public static func guessCode(for name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = commonLanguageMap[clean] {
            return exact
        }
        for (key, code) in commonLanguageMap where clean.contains(key) {
            return code
        }
        if clean.count >= 2 {
            return String(clean.prefix(2))
        }
        return ""
    }
}