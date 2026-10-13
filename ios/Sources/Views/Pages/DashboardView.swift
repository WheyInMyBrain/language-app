import SwiftUI

public struct DashboardView: View {
    @Bindable var metadata = MetadataStore.shared
    @Bindable var srs = SRSStore.shared
    public var onSelectDate: (String) -> Void
    public var onOpenQuiz: () -> Void

    public init(
        onSelectDate: @escaping (String) -> Void,
        onOpenQuiz: @escaping () -> Void
    ) {
        self.onSelectDate = onSelectDate
        self.onOpenQuiz = onOpenQuiz
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // 1. Language Header Pill & Status
                languageStatusBar

                // 2. High-Performance Concentric Rings & Schedule Deck
                TodayTasksView(onSelectDate: onSelectDate)

                // 3. Virtualized Horizontal Vocab Search Track
                VocabSearchStreamView(onSelectDate: onSelectDate)

                // 4. Metrics, Milestones, Growth Chart & Heatmap
                DashboardMetricsView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            VocabIndexStore.shared.connect(langCode: metadata.activeLanguage)
        }
        .onChange(of: metadata.activeLanguage) { _, newLang in
            VocabIndexStore.shared.connect(langCode: newLang)
        }
    }

    private var languageStatusBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(metadata.connectionStatus == "connected" ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(metadata.activeLanguage)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            // Streak Counter Badge
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                let streak = metadata.languages[metadata.activeLanguage]?.current_streak ?? 0
                Text("\(streak)d")
                    .font(.caption.monospacedDigit().bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
}