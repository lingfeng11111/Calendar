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
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-fixture") {
                try? vacationRepository.resetForTesting()
                try? vacationRepository.seedIfEmpty(with: PersonalDateFixtures.sample)
                try? scheduleRepository.resetForTesting()
                try? scheduleRepository.seedIfEmpty(with: ScheduleFixtures.sample)
            }
            _dependencies = State(
                initialValue: AppDependencies(
                    holidayRepository: HolidayRepository(
                        modelContext: context,
                        primaryProvider: HolidayCNProvider(),
                        backupProvider: AILCCHolidayProvider()
                    ),
                    vacationRepository: vacationRepository,
                    scheduleRepository: scheduleRepository,
                    dateKnowledgeRepository: DateKnowledgeRepository(
                        modelContext: context,
                        primaryProvider: SolarTermsDateKnowledgeProvider()
                    ),
                    systemCalendarService: EventKitSystemCalendarService()
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
