import SwiftUI

@MainActor
struct AppView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .calendar
    @State private var calendarRouter = AppRouter()
    @State private var vacationRouter = AppRouter()
    @State private var settingsRouter = AppRouter()

    init() {
        _selectedTab = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-ui-testing-vacation")
                ? .vacation
                : .calendar
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tabRoot(
                CalendarScreen(
                    repository: dependencies.holidayRepository,
                    vacationRepository: dependencies.vacationRepository,
                    scheduleRepository: dependencies.scheduleRepository,
                    dateKnowledgeRepository: dependencies.dateKnowledgeRepository
                ),
                router: calendarRouter
            )
                .tabItem { AppTab.calendar.label }
                .tag(AppTab.calendar)
                .accessibilityIdentifier("tab.calendar")

            tabRoot(
                VacationScreen(repository: dependencies.vacationRepository),
                router: vacationRouter
            )
                .tabItem { AppTab.vacation.label }
                .tag(AppTab.vacation)
                .accessibilityIdentifier("tab.vacation")

            tabRoot(
                SettingsScreen(
                    systemCalendarService: dependencies.systemCalendarService,
                    systemCalendarSelectionStore: dependencies.systemCalendarSelectionStore,
                    notificationService: dependencies.notificationService,
                    holidayRepository: dependencies.holidayRepository,
                    vacationRepository: dependencies.vacationRepository,
                    scheduleRepository: dependencies.scheduleRepository,
                    notificationPreferencesStore: dependencies.notificationPreferencesStore
                ),
                router: settingsRouter
            )
                .tabItem { AppTab.settings.label }
                .tag(AppTab.settings)
                .accessibilityIdentifier("tab.settings")
        }
        .tint(dependencies.theme.tint)
        .task {
            await dependencies.widgetSnapshotCoordinator?.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            Task {
                await dependencies.widgetSnapshotCoordinator?.refresh()
            }
        }
    }

    private func tabRoot<Content: View>(_ content: Content, router: AppRouter) -> some View {
        NavigationStack(
            path: Binding(
                get: { router.path },
                set: { router.path = $0 }
            )
        ) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(router)
        .appSheetDestinations(
            sheet: Binding(
                get: { router.presentedSheet },
                set: { router.presentedSheet = $0 }
            )
        )
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .dayDetail(dayID):
            DayDetailScreen(
                dayID: dayID,
                repository: dependencies.holidayRepository,
                vacationRepository: dependencies.vacationRepository,
                scheduleRepository: dependencies.scheduleRepository,
                dateKnowledgeRepository: dependencies.dateKnowledgeRepository,
                systemCalendarService: dependencies.systemCalendarService,
                systemCalendarSelectionStore: dependencies.systemCalendarSelectionStore
            )
        case .settings:
            SettingsScreen(
                systemCalendarService: dependencies.systemCalendarService,
                systemCalendarSelectionStore: dependencies.systemCalendarSelectionStore,
                notificationService: dependencies.notificationService,
                holidayRepository: dependencies.holidayRepository,
                vacationRepository: dependencies.vacationRepository,
                scheduleRepository: dependencies.scheduleRepository,
                notificationPreferencesStore: dependencies.notificationPreferencesStore
            )
        }
    }
}

private struct PlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "功能尚未接入",
                systemImage: "hammer",
                description: Text("这个 Sheet 路由已经预留，功能将在后续阶段实现。")
            )
            .navigationTitle("准备中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func appSheetDestinations(sheet: Binding<SheetDestination?>) -> some View {
        self.sheet(item: sheet) { destination in
            switch destination {
            case .placeholder:
                PlaceholderSheet()
            }
        }
    }
}

#Preview("应用壳") {
    AppView()
        .environment(AppDependencies())
        .environment(Theme())
}
