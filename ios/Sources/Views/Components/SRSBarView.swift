import SwiftUI

private struct ProjectedGradeOption: Identifiable {
    let grade: SRSGrade
    let label: String
    let intervalDays: Int
    let color: Color
    var id: UInt8 { grade.rawValue }
}

public struct SRSBarView: View {
    public let session: DaySessionMeta
    public let activeDate: String
    public var onReview: (SRSGrade) -> Void

    @State private var isSubmitting: Bool = false
    @State private var statusMessage: String? = nil
    @State private var lastGraded: SRSGrade? = nil

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    public init(
        session: DaySessionMeta,
        activeDate: String,
        onReview: @escaping (SRSGrade) -> Void
    ) {
        self.session = session
        self.activeDate = activeDate
        self.onReview = onReview
    }

    private var curRev: Int { session.revision }
    private var curInterval: Double { session.interval }
    private var curEase: Double { session.ease }

    private var formattedDueDate: String {
        if session.due_date.isEmpty || session.due_date == activeDate {
            return "Today"
        }
        return session.due_date
    }

    private var projectedGrades: [ProjectedGradeOption] {
        [
            ProjectedGradeOption(
                grade: .again,
                label: "Again",
                intervalDays: max(1, Int(SRSEngine.calculateNextState(currentRev: curRev, currentInterval: curInterval, currentEase: curEase, grade: .again, todayStr: activeDate).interval.rounded())),
                color: Color.red
            ),
            ProjectedGradeOption(
                grade: .hard,
                label: "Hard",
                intervalDays: max(1, Int(SRSEngine.calculateNextState(currentRev: curRev, currentInterval: curInterval, currentEase: curEase, grade: .hard, todayStr: activeDate).interval.rounded())),
                color: Color.orange
            ),
            ProjectedGradeOption(
                grade: .good,
                label: "Good",
                intervalDays: max(1, Int(SRSEngine.calculateNextState(currentRev: curRev, currentInterval: curInterval, currentEase: curEase, grade: .good, todayStr: activeDate).interval.rounded())),
                color: lang.vocabColor
            ),
            ProjectedGradeOption(
                grade: .easy,
                label: "Easy",
                intervalDays: max(1, Int(SRSEngine.calculateNextState(currentRev: curRev, currentInterval: curInterval, currentEase: curEase, grade: .easy, todayStr: activeDate).interval.rounded())),
                color: lang.grammarColor
            )
        ]
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Tier 1: Telemetry Meta Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(lang.themeColor)
                        .frame(width: 6, height: 6)
                    Text(curRev < 2 ? "Pass \(curRev)" : "Pass \(curRev) (Mature)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(lang.themeColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(lang.themeColor.opacity(0.12))
                .clipShape(Capsule())

                HStack(spacing: 6) {
                    telemetryBadge(title: "Int", value: "\(Int(curInterval))d", icon: "calendar")
                    telemetryBadge(title: "Ease", value: String(format: "%.2fx", curEase), icon: "chart.line.uptrend.xyaxis")
                    telemetryBadge(title: "Due", value: formattedDueDate, icon: "checkmark.shield")
                }

                Spacer()

                if let status = statusMessage {
                    Text(status)
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(lang.themeColor)
                        .transition(.opacity)
                }
            }

            // Tier 2: Action Controls
            if curRev < 2 {
                Button {
                    handleGrade(.good)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.caption.bold())
                        Text("Advance to Pass \(curRev + 1)")
                            .font(.subheadline.bold())
                        Image(systemName: "arrow.right")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(lang.themeColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: lang.themeColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(SRSSquishButtonStyle())
                .disabled(isSubmitting)
            } else {
                HStack(spacing: 6) {
                    ForEach(projectedGrades) { opt in
                        let isSelected = lastGraded == opt.grade
                        Button {
                            handleGrade(opt.grade)
                        } label: {
                            VStack(spacing: 2) {
                                Text(opt.label)
                                    .font(.caption2.bold())
                                Text("+\(opt.intervalDays)d")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? opt.color : opt.color.opacity(0.14))
                            .foregroundStyle(isSelected ? .white : opt.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(opt.color.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(SRSSquishButtonStyle())
                        .disabled(isSubmitting)
                    }
                }
            }
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.85))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.20))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.65), location: 0.0),
                            .init(color: lang.themeColor.opacity(0.30), location: 0.4),
                            .init(color: Color.white.opacity(0.12), location: 0.8),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .sensoryFeedback(.impact(weight: .medium), trigger: lastGraded)
    }

    private func telemetryBadge(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text("\(title):")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .tertiarySystemFill).opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func handleGrade(_ grade: SRSGrade) {
        self.isSubmitting = true
        self.lastGraded = grade
        self.statusMessage = "Saving..."

        onReview(grade)

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.statusMessage = nil
            self.lastGraded = nil
            self.isSubmitting = false
        }
    }
}

private struct SRSSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}