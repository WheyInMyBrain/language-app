import SwiftUI

public enum LanguageConfigDefaults {
    public static let goals = LanguageGoals(
        vocab: 10,
        grammar: 1,
        ci: 1,
        listening: 45,
        speaking: 10
    )

    public static let milestones = LanguageMilestones(
        vocab: 1000,
        listening: 48,
        speaking: 12
    )

    public static let momentum = LanguageMomentumConfig(
        listening: MetricMomentumConfig(floor: 20, baseline: 45, ceiling: 90, halfLife: 2.5, slewRate: 15),
        speaking: MetricMomentumConfig(floor: 5, baseline: 10, ceiling: 25, halfLife: 2.5, slewRate: 5),
        vocab: MetricMomentumConfig(floor: 2, baseline: 5, ceiling: 10, halfLife: 2.5, slewRate: 2),
        srs: SRSPacingConfig(
            vision: MetricMomentumConfig(floor: 10, baseline: 20, ceiling: 35),
            listen: MetricMomentumConfig(floor: 5, baseline: 10, ceiling: 20),
            write: MetricMomentumConfig(floor: 1, baseline: 3, ceiling: 5)
        ),
        revisions: MetricMomentumConfig(floor: 1, baseline: 1, ceiling: 2)
    )

    public static let colors = LanguageColors(
        theme: ColorShades(dark: "#c084fc", light: "#7e22ce", primary: "#a855f7"),
        streak: ColorShades(dark: "#fb7185", light: "#e11d48", primary: "#f43f5e"),
        vocab: ColorShades(dark: "#34d399", light: "#059669", primary: "#10b981"),
        ci: ColorShades(dark: "#d8b4fe", light: "#9333ea", primary: "#a855f7"),
        listening: ColorShades(dark: "#fb923c", light: "#ea580c", primary: "#f97316"),
        speaking: ColorShades(dark: "#e879f9", light: "#a21caf", primary: "#c026d3"),
        grammar: ColorShades(dark: "#38bdf8", light: "#0284c7", primary: "#0ea5e9"),
        flashcard: ColorShades(dark: "#f472b6", light: "#db2777", primary: "#ec4899")
    )
}