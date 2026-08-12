import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotCoordinator {
    private let holidayRepository: (any HolidayRepositoryProtocol)?
    private let vacationRepository: (any VacationRepositoryProtocol)?
    private let scheduleRepository: (any ScheduleRepositoryProtocol)?
    private let dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?
    private let store: CalendarWidgetSnapshotStore

    init(
        holidayRepository: (any HolidayRepositoryProtocol)?,
        vacationRepository: (any VacationRepositoryProtocol)?,
        scheduleRepository: (any ScheduleRepositoryProtocol)?,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?,
        store: CalendarWidgetSnapshotStore = CalendarWidgetSnapshotStore()
    ) {
        self.holidayRepository = holidayRepository
        self.vacationRepository = vacationRepository
        self.scheduleRepository = scheduleRepository
        self.dateKnowledgeRepository = dateKnowledgeRepository
        self.store = store
    }

    func refresh(referenceDate: Date = .now) async {
        let model = CalendarFeatureModel(
            repository: holidayRepository,
            vacationRepository: vacationRepository,
            scheduleRepository: scheduleRepository,
            dateKnowledgeRepository: dateKnowledgeRepository,
            initialDate: referenceDate
        )
        await model.load()

        let snapshot = CalendarWidgetSnapshotComposer().makeSnapshot(
            referenceDate: referenceDate,
            presentation: model.presentation(for: model.today),
            upcomingDates: model.upcomingDates
        )

        do {
            try store.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetSnapshot.widgetKind)
        } catch {
            // A Widget failure must not affect the main calendar experience.
        }
    }
}
