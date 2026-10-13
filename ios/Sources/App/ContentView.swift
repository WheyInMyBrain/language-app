import SwiftUI

struct ContentView: View {
    @Bindable var metadata = MetadataStore.shared

    // Exact order: Settings, Library, Dashboard, Quiz, Daily
    enum TabItem: String, CaseIterable, Identifiable, Hashable {
        case settings = "Settings"
        case library = "Library"
        case dashboard = "Dashboard"
        case quiz = "Quiz"
        case day = "Daily"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .settings: return "gearshape.fill"
            case .library: return "books.vertical.fill"
            case .dashboard: return "gauge.with.needle"
            case .quiz: return "brain.head.profile"
            case .day: return "calendar.day.timeline.left"
            }
        }
    }

    @State private var selectedTab: TabItem = .dashboard
    @State private var navigationPath = NavigationPath()
    
    // Remembers which tab initiated the drill-down into DayView
    @State private var returnTabAfterDayView: TabItem? = nil

    private var activeContext: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    /// Helper to navigate to a date from any other tab while preserving return history
    private func drillIntoDay(date: String, from sourceTab: TabItem) {
        returnTabAfterDayView = sourceTab
        selectedTab = .day
        navigationPath.append(date)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Settings
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: TabItem.settings.icon)
            }
            .tag(TabItem.settings)

            // MARK: - Library
            NavigationStack {
                LibraryPageView(
                    onSelectDate: { date in
                        drillIntoDay(date: date, from: .library)
                    }
                )
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: TabItem.library.icon)
            }
            .tag(TabItem.library)

            // MARK: - Dashboard
            NavigationStack {
                DashboardView(
                    onSelectDate: { date in
                        drillIntoDay(date: date, from: .dashboard)
                    },
                    onOpenQuiz: {
                        selectedTab = .quiz
                    }
                )
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: TabItem.dashboard.icon)
            }
            .tag(TabItem.dashboard)

            // MARK: - Quiz
            NavigationStack {
                QuizPageView(
                    langCode: metadata.activeLanguage,
                    onSelectDate: { date in
                        drillIntoDay(date: date, from: .quiz)
                    }
                )
                .navigationTitle("Quiz")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: TabItem.quiz.icon)
            }
            .tag(TabItem.quiz)

            // MARK: - Daily
            NavigationStack(path: $navigationPath) {
                DayListView(langCode: metadata.activeLanguage)
                    .navigationDestination(for: String.self) { dateStr in
                        DayView(
                            date: dateStr,
                            langCode: metadata.activeLanguage,
                            onSelectDate: { _ in }
                        )
                        .toolbar(.hidden, for: .tabBar) // Hides tab bar naturally on drill-down
                    }
            }
            .tabItem {
                Image(systemName: TabItem.day.icon)
            }
            .tag(TabItem.day)
        }
        .tint(activeContext.themeColor)
        // Detects when the user pops off DayView back to the root of the stack
        .onChange(of: navigationPath.count) { _, newCount in
            if newCount == 0, let target = returnTabAfterDayView {
                returnTabAfterDayView = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                    selectedTab = target
                }
            }
        }
    }
}