import Foundation
import Observation

enum CalendarDataState: Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case loaded
    case refreshFailed
    case notPublished
    case unavailable
}

struct MonthOverview: Equatable, Sendable {
    let month: CalendarMonth
    let restDayCount: Int
    let makeupWorkdayCount: Int
    let vacationDayCount: Int
    let scheduleCount: Int
    let annotationCount: Int

    static func empty(for month: CalendarMonth) -> MonthOverview {
        MonthOverview(
            month: month,
            restDayCount: 0,
            makeupWorkdayCount: 0,
            vacationDayCount: 0,
            scheduleCount: 0,
            annotationCount: 0
        )
    }
}

struct UpcomingDateSummary: Equatable, Hashable, Identifiable, Sendable {
    let dayID: DayID
    let title: String
    let subtitle: String?
    let kind: DayAnnotationKind?
    let scheduleCount: Int

    var id: String {
        "\(dayID.description)|\(title)|\(kind?.rawValue ?? "schedule")"
    }
}

@MainActor
@Observable
final class CalendarFeatureModel {
    @ObservationIgnored let repository: (any HolidayRepositoryProtocol)?
    @ObservationIgnored let vacationRepository: (any VacationRepositoryProtocol)?
    @ObservationIgnored let scheduleRepository: (any ScheduleRepositoryProtocol)?
    @ObservationIgnored let dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?
    @ObservationIgnored private let compositionService: DayCompositionService

    let today: DayID
    var displayedMonth: CalendarMonth
    var selectedDayID: DayID?
    var dataState: CalendarDataState = .idle
    var presentations: [DayID: DayPresentation] = [:]
    var monthOverview: MonthOverview
    var upcomingDates: [UpcomingDateSummary] = []
    var dateKnowledgeSnapshot: DateKnowledgeYearSnapshot?
    var errorMessage: String?

    init(
        repository: (any HolidayRepositoryProtocol)?,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        initialDate: Date = .now,
        compositionService: DayCompositionService = DayCompositionService()
    ) {
        let dayID = DayID(initialDate)
        self.repository = repository
        self.vacationRepository = vacationRepository
        self.scheduleRepository = scheduleRepository
        self.dateKnowledgeRepository = dateKnowledgeRepository
        self.compositionService = compositionService
        self.today = dayID
        let initialMonth = CalendarMonth(year: dayID.year, month: dayID.month)!
        self.displayedMonth = initialMonth
        self.monthOverview = .empty(for: initialMonth)
    }

    var grid: CalendarMonthGrid {
        CalendarMonthGrid(month: displayedMonth)
    }

    func presentation(for dayID: DayID) -> DayPresentation {
        presentations[dayID]
            ?? compositionService.compose(
                dayID: dayID,
                holidayState: .unavailable
            )
    }

    func isToday(_ dayID: DayID) -> Bool {
        dayID == today
    }

    func moveMonth(by value: Int) {
        guard let month = displayedMonth.adding(months: value) else {
            return
        }

        displayedMonth = month
        selectedDayID = nil
        dataState = .idle
        presentations = [:]
        dateKnowledgeSnapshot = nil
        monthOverview = .empty(for: displayedMonth)
        upcomingDates = []
        errorMessage = nil
    }

    func goToToday() {
        guard let month = CalendarMonth(year: today.year, month: today.month) else {
            return
        }

        displayedMonth = month
        selectedDayID = today
        dataState = .idle
        presentations = [:]
        dateKnowledgeSnapshot = nil
        monthOverview = .empty(for: displayedMonth)
        upcomingDates = []
        errorMessage = nil
    }

    func load() async {
        guard !Task.isCancelled else {
            return
        }

        let targetMonth = displayedMonth
        errorMessage = nil
        let personalSnapshot = personalDateSnapshot(for: targetMonth.year)
        let scheduleSnapshot = scheduleSnapshot(for: targetMonth.year)
        async let knowledgeTask = dateKnowledgeSnapshot(for: targetMonth.year)

        guard let repository else {
            let knowledgeSnapshot = await knowledgeTask
            apply(
                holidayState: previewState(for: targetMonth.year),
                month: targetMonth,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
            return
        }

        let hasVisibleContent = !presentations.isEmpty
        dataState = hasVisibleContent ? .refreshing : .loading

        do {
            let snapshot = try await repository.snapshot(for: targetMonth.year)
            guard !Task.isCancelled, displayedMonth == targetMonth else {
                return
            }

            apply(
                holidayState: .available(snapshot),
                month: targetMonth,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: nil
            )

            let knowledgeSnapshot = await knowledgeTask
            guard !Task.isCancelled, displayedMonth == targetMonth else {
                return
            }
            guard let knowledgeSnapshot else {
                return
            }

            apply(
                holidayState: .available(snapshot),
                month: targetMonth,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
        } catch is CancellationError {
            return
        } catch let error as HolidayRepositoryError {
            guard displayedMonth == targetMonth else {
                return
            }

            switch error {
            case .notPublished:
                guard !hasVisibleContent else {
                    errorMessage = "最新节假日安排尚未发布，继续显示上次有效数据"
                    dataState = .refreshFailed
                    return
                }

                errorMessage = error.localizedDescription
                apply(
                    holidayState: .notPublished,
                    month: targetMonth,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: nil
                )

                let knowledgeSnapshot = await knowledgeTask
                guard displayedMonth == targetMonth, let knowledgeSnapshot else {
                    return
                }
                apply(
                    holidayState: .notPublished,
                    month: targetMonth,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: knowledgeSnapshot
                )
            case .invalidYear, .providersUnavailable, .persistenceFailed:
                guard !hasVisibleContent else {
                    errorMessage = "刷新失败，继续显示上次有效数据"
                    dataState = .refreshFailed
                    return
                }

                errorMessage = error.localizedDescription
                apply(
                    holidayState: .unavailable,
                    month: targetMonth,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: nil
                )

                let knowledgeSnapshot = await knowledgeTask
                guard displayedMonth == targetMonth, let knowledgeSnapshot else {
                    return
                }
                apply(
                    holidayState: .unavailable,
                    month: targetMonth,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: knowledgeSnapshot
                )
            }
        } catch {
            guard displayedMonth == targetMonth else {
                return
            }

            guard !hasVisibleContent else {
                errorMessage = "刷新失败，继续显示上次有效数据"
                dataState = .refreshFailed
                return
            }

            errorMessage = "节假日数据暂不可用"
            apply(
                holidayState: .unavailable,
                month: targetMonth,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: nil
            )

            let knowledgeSnapshot = await knowledgeTask
            guard displayedMonth == targetMonth, let knowledgeSnapshot else {
                return
            }
            apply(
                holidayState: .unavailable,
                month: targetMonth,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
        }
    }

    private func apply(
        holidayState: HolidayYearRefreshState,
        month: CalendarMonth,
        personalSnapshot: PersonalDateSnapshot?,
        scheduleSnapshot: ScheduleSnapshot?,
        dateKnowledgeSnapshot: DateKnowledgeYearSnapshot?
    ) {
        let dayIDs = CalendarMonthGrid(month: month).days.map(\.dayID)
        self.dateKnowledgeSnapshot = dateKnowledgeSnapshot
        presentations = compositionService.compose(
            dayIDs: dayIDs,
            holidayState: holidayState,
            vacationPeriods: personalSnapshot?.vacationPeriods ?? [],
            specialDays: personalSnapshot?.specialDays ?? [],
            schedules: scheduleSnapshot?.items ?? [],
            dateKnowledgeSnapshot: dateKnowledgeSnapshot
        )
        monthOverview = makeMonthOverview(
            month: month,
            personalSnapshot: personalSnapshot
        )
        upcomingDates = makeUpcomingDates(month: month)

        switch holidayState {
        case .available:
            dataState = .loaded
        case .notPublished:
            dataState = .notPublished
        case .unavailable:
            dataState = .unavailable
        }
    }

    private func personalDateSnapshot(for year: Int) -> PersonalDateSnapshot? {
        guard let vacationRepository else {
            return nil
        }

        return try? vacationRepository.snapshot(for: year)
    }

    private func scheduleSnapshot(for year: Int) -> ScheduleSnapshot? {
        guard let scheduleRepository else {
            return nil
        }

        return try? scheduleRepository.snapshot(for: year)
    }

    private func dateKnowledgeSnapshot(for year: Int) async -> DateKnowledgeYearSnapshot? {
        guard let dateKnowledgeRepository else {
            return repository == nil ? previewKnowledgeState(for: year) : nil
        }

        return try? await dateKnowledgeRepository.snapshot(for: year)
    }

    private func makeMonthOverview(
        month: CalendarMonth,
        personalSnapshot: PersonalDateSnapshot?
    ) -> MonthOverview {
        let monthDayIDs = CalendarMonthGrid(month: month).days
            .filter(\.isInDisplayedMonth)
            .map(\.dayID)
        let monthPresentations = monthDayIDs.map { presentation(for: $0) }
        let vacationDayCount = monthDayIDs.reduce(into: 0) { count, dayID in
            if personalSnapshot?.vacationPeriods.contains(where: { $0.contains(dayID) }) == true {
                count += 1
            }
        }

        return MonthOverview(
            month: month,
            restDayCount: monthPresentations.filter { $0.workStatus.isOffDay == true }.count,
            makeupWorkdayCount: monthPresentations.filter { $0.workStatus == .makeupWorkday }.count,
            vacationDayCount: vacationDayCount,
            scheduleCount: monthPresentations.reduce(0) { $0 + $1.scheduleCount },
            annotationCount: monthPresentations.filter { $0.primaryAnnotation != nil }.count
        )
    }

    private func makeUpcomingDates(month: CalendarMonth) -> [UpcomingDateSummary] {
        let dayIDs = CalendarMonthGrid(month: month).days
            .filter(\.isInDisplayedMonth)
            .map(\.dayID)
        let currentMonth = CalendarMonth(year: today.year, month: today.month)
        let baseline = displayedMonth == currentMonth ? today : dayIDs.first

        var summaries: [UpcomingDateSummary] = []
        for dayID in dayIDs where baseline.map({ dayID >= $0 }) ?? true {
            let presentation = presentation(for: dayID)
            if let annotation = presentation.primaryAnnotation {
                summaries.append(
                    UpcomingDateSummary(
                        dayID: dayID,
                        title: annotation.title,
                        subtitle: annotation.kind.displayName,
                        kind: annotation.kind,
                        scheduleCount: presentation.scheduleCount
                    )
                )
            } else if presentation.scheduleCount > 0 {
                summaries.append(
                    UpcomingDateSummary(
                        dayID: dayID,
                        title: "本地日程",
                        subtitle: "\(presentation.scheduleCount) 项",
                        kind: nil,
                        scheduleCount: presentation.scheduleCount
                    )
                )
            }
        }

        return Array(summaries.sorted { $0.dayID < $1.dayID }.prefix(6))
    }

    private func previewState(for year: Int) -> HolidayYearRefreshState {
        guard let newYear = DayID(year: year, month: 1, day: 1),
              let snapshot = try? HolidayYearSnapshot(
                  year: year,
                  providerID: "preview",
                  fetchedAt: Date(timeIntervalSince1970: 0),
                  sourceURL: URL(string: "https://example.test/preview/\(year).json"),
                  records: [
                      HolidayRecord(
                          dayID: newYear,
                          name: "元旦",
                          kind: .holiday
                      )
                  ]
              ) else {
            return .unavailable
        }

        return .available(snapshot)
    }

    private func previewKnowledgeState(for year: Int) -> DateKnowledgeYearSnapshot? {
        guard let solarTermDay = DayID(year: year, month: 1, day: 5),
              let festivalDay = DayID(year: year, month: 1, day: 18) else {
            return nil
        }

        return try? DateKnowledgeYearSnapshot(
            year: year,
            providerID: "preview",
            fetchedAt: Date(timeIntervalSince1970: 0),
            sourceURL: URL(string: "https://example.test/date-knowledge/\(year).json"),
            annotations: [
                DayAnnotation(
                    dayID: solarTermDay,
                    title: "小寒",
                    kind: .solarTerm,
                    sourceID: "preview"
                ),
                DayAnnotation(
                    dayID: festivalDay,
                    title: "传统节日示例",
                    kind: .importantTraditionalFestival,
                    sourceID: "preview"
                )
            ]
        )
    }
}
