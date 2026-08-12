import SwiftData
import SwiftUI

@main
struct CalendarApp: App {
    @State private var dependencies: AppDependencies
    private let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(
                for: AppPreferenceModel.self,
                HolidaySnapshotModel.self,
                CachedHolidayRecordModel.self,
                VacationPeriodModel.self,
                SpecialDayModel.self,
                LocalScheduleItemModel.self,
                DateKnowledgeSnapshotModel.self
            )
            modelContainer = container

            let context = ModelContext(container)
            let vacationRepository = VacationRepository(modelContext: context)
            let scheduleRepository = ScheduleRepository(modelContext: context)
            let systemCalendarSelectionStore = SwiftDataSystemCalendarSelectionStore(modelContext: context)
            let notificationPreferencesStore = SwiftDataNotificationPreferencesStore(modelContext: context)
            let holidayRepository = HolidayRepository(
                modelContext: context,
                primaryProvider: HolidayCNProvider(),
                backupProvider: AILCCHolidayProvider()
            )
            let dateKnowledgeRepository = DateKnowledgeRepository(
                modelContext: context,
                primaryProvider: CompositeDateKnowledgeProvider(
                    providers: [
                        ChineseTraditionalFestivalProvider(),
                        SolarTermsResilientProvider()
                    ]
                ),
                fallbackProvider: SolarTermsAlgorithmProvider()
            )
            let widgetSnapshotCoordinator = WidgetSnapshotCoordinator(
                holidayRepository: holidayRepository,
                vacationRepository: vacationRepository,
                scheduleRepository: scheduleRepository,
                dateKnowledgeRepository: dateKnowledgeRepository
            )
            let systemCalendarService: any SystemCalendarServiceProtocol =
                ProcessInfo.processInfo.arguments.contains("-ui-testing-system-calendar")
                    ? FixtureSystemCalendarService()
                    : EventKitSystemCalendarService()
            let notificationService: any NotificationServiceProtocol =
                ProcessInfo.processInfo.arguments.contains("-ui-testing-fixture")
                    ? FixtureNotificationService()
                    : UserNotificationsService()

            if ProcessInfo.processInfo.arguments.contains("-ui-testing-system-calendar") {
                try? systemCalendarSelectionStore.save(selectedCalendarIDs: nil)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-fixture") {
                try? notificationPreferencesStore.save(nil)
                try? vacationRepository.resetForTesting()
                try? vacationRepository.seedIfEmpty(with: PersonalDateFixtures.sample)
                try? scheduleRepository.resetForTesting()
                try? scheduleRepository.seedIfEmpty(with: ScheduleFixtures.sample)
            }
            _dependencies = State(
                initialValue: AppDependencies(
                    holidayRepository: holidayRepository,
                    vacationRepository: vacationRepository,
                    scheduleRepository: scheduleRepository,
                    dateKnowledgeRepository: dateKnowledgeRepository,
                    systemCalendarService: systemCalendarService,
                    systemCalendarSelectionStore: systemCalendarSelectionStore,
                    notificationService: notificationService,
                    notificationPreferencesStore: notificationPreferencesStore,
                    widgetSnapshotCoordinator: widgetSnapshotCoordinator
                )
            )
        } catch {
            fatalError("Unable to create the app model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(dependencies)
                .environment(dependencies.theme)
        }
        .modelContainer(modelContainer)
    }
}
