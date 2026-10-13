import SwiftUI
import Observation

extension Color {
    init(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

@Observable
public final class ActiveLanguageContext {
    public static let shared = ActiveLanguageContext()

    public private(set) var code: String = ""
    public private(set) var strategy: any LanguageStrategy = LanguageRegistry.strategy(for: "zh-CN")
    public private(set) var isRTL: Bool = false

    public private(set) var themeColor: Color = .purple
    public private(set) var vocabColor: Color = .green
    public private(set) var listeningColor: Color = .orange
    public private(set) var speakingColor: Color = .pink
    public private(set) var grammarColor: Color = .cyan
    public private(set) var tonePalette: [Int: Color] = [:]

    private init() {
        updateLanguage(code: MetadataStore.shared.activeLanguage)
    }

    public func updateLanguage(code: String) {
        guard self.code != code else { return }
        self.code = code
        let strat = LanguageRegistry.strategy(for: code)
        self.strategy = strat
        self.isRTL = strat.isRTL

        self.themeColor = strat.defaultColors.theme?.swiftUIColor ?? .purple
        self.vocabColor = strat.defaultColors.vocab?.swiftUIColor ?? .green
        self.listeningColor = strat.defaultColors.listening?.swiftUIColor ?? .orange
        self.speakingColor = strat.defaultColors.speaking?.swiftUIColor ?? .pink
        self.grammarColor = strat.defaultColors.grammar?.swiftUIColor ?? .cyan

        var palette: [Int: Color] = [:]
        for (tone, hex) in strat.defaultTones {
            palette[tone] = Color(hexString: hex)
        }
        self.tonePalette = palette
    }

    public func colorize(primary: String, secondary: String) -> TokenizedPhonetics {
        strategy.colorize(primary: primary, secondary: secondary, palette: tonePalette)
    }
}