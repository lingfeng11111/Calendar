import Observation

@MainActor
@Observable
final class AppDependencies {
    let theme: Theme
    let holidayRepository: (any HolidayRepositoryProtocol)?
    let vacationRepository: (any VacationRepositoryProtocol)?
    let scheduleRepository: (any ScheduleRepositoryProtocol)?
    let dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?
    let systemCalendarService: (any SystemCalendarServiceProtocol)?

    init(
        theme: Theme = Theme(),
        holidayRepository: (any HolidayRepositoryProtocol)? = nil,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        systemCalendarService: (any SystemCalendarServiceProtocol)? = nil
    ) {
        self.theme = theme
        self.holidayRepository = holidayRepository
        self.vacationRepository = vacationRepository
        self.scheduleRepository = scheduleRepository
        self.dateKnowledgeRepository = dateKnowledgeRepository
        self.systemCalendarService = systemCalendarService
    }
}
