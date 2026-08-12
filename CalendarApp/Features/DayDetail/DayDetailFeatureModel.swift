import Foundation
import Observation

enum DayDetailDataState: Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case loaded
    case refreshFailed
    case notPublished
    case unavailable
}

enum DayDetailSystemCalendarState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case filteredOut
    case permissionRequired
    case accessDenied
    case accessRestricted
    case unavailable
    case failed
}

@MainActor
@Observable
final class DayDetailFeatureModel {
    @ObservationIgnored let repository: (any HolidayRepositoryProtocol)?
    @ObservationIgnored let vacationRepository: (any VacationRepositoryProtocol)?
    @ObservationIgnored let scheduleRepository: (any ScheduleRepositoryProtocol)?
    @ObservationIgnored let dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?
    @ObservationIgnored let systemCalendarService: (any SystemCalendarServiceProtocol)?
    @ObservationIgnored let systemCalendarSelectionStore: (any SystemCalendarSelectionStoreProtocol)?
    @ObservationIgnored private let compositionService: DayCompositionService

    let dayID: DayID
    var dataState: DayDetailDataState = .idle
    var presentation: DayPresentation
    var sourceURL: URL?
    var fetchedAt: Date?
    var dateKnowledgeProviderID: String? = nil
    var dateKnowledgeSourceURL: URL? = nil
    var dateKnowledgeFetchedAt: Date? = nil
    var errorMessage: String?
    var scheduleItems: [ScheduleItem] = []
    var systemCalendarAccess: SystemCalendarAccess
    var systemCalendarState: DayDetailSystemCalendarState
    var systemCalendarEvents: [SystemCalendarEventSnapshot] = []
    var selectedSystemCalendarIDs: Set<String>?
    var systemCalendarErrorMessage: String?

    init(
        dayID: DayID,
        repository: (any HolidayRepositoryProtocol)?,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        systemCalendarService: (any SystemCalendarServiceProtocol)? = nil,
        systemCalendarSelectionStore: (any SystemCalendarSelectionStoreProtocol)? = nil,
        compositionService: DayCompositionService = DayCompositionService()
    ) {
        self.dayID = dayID
        self.repository = repository
        self.vacationRepository = vacationRepository
        self.scheduleRepository = scheduleRepository
        self.dateKnowledgeRepository = dateKnowledgeRepository
        self.systemCalendarService = systemCalendarService
        self.systemCalendarSelectionStore = systemCalendarSelectionStore
        self.compositionService = compositionService
        self.systemCalendarAccess = systemCalendarService?.access ?? .unavailable
        self.systemCalendarState = systemCalendarService == nil ? .unavailable : .idle
        self.selectedSystemCalendarIDs = nil
        self.presentation = compositionService.compose(
            dayID: dayID,
            holidayState: .unavailable
        )
    }

    func load() async {
        guard !Task.isCancelled else {
            return
        }

        errorMessage = nil
        let personalSnapshot = personalDateSnapshot()
        let scheduleSnapshot = scheduleSnapshot()
        async let knowledgeTask = dateKnowledgeSnapshot()
        async let systemCalendarTask: Void = loadSystemCalendarEvents()

        guard let repository else {
            let knowledgeSnapshot = await knowledgeTask
            apply(
                holidayState: previewState(for: dayID.year),
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
            await systemCalendarTask
            return
        }

        let hasVisibleContent = dataState == .loaded || dataState == .refreshFailed
        dataState = hasVisibleContent ? .refreshing : .loading

        do {
            let snapshot = try await repository.snapshot(for: dayID.year)
            guard !Task.isCancelled else {
                return
            }

            apply(
                holidayState: .available(snapshot),
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: nil
            )

            let knowledgeSnapshot = await knowledgeTask
            guard !Task.isCancelled, let knowledgeSnapshot else {
                return
            }
            apply(
                holidayState: .available(snapshot),
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
            await systemCalendarTask
        } catch is CancellationError {
            return
        } catch let error as HolidayRepositoryError {
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
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: nil
                )

                let knowledgeSnapshot = await knowledgeTask
                guard let knowledgeSnapshot else {
                    return
                }
                apply(
                    holidayState: .notPublished,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: knowledgeSnapshot
                )
                await systemCalendarTask
            case .invalidYear, .providersUnavailable, .persistenceFailed:
                guard !hasVisibleContent else {
                    errorMessage = "刷新失败，继续显示上次有效数据"
                    dataState = .refreshFailed
                    return
                }

                errorMessage = error.localizedDescription
                apply(
                    holidayState: .unavailable,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: nil
                )

                let knowledgeSnapshot = await knowledgeTask
                guard let knowledgeSnapshot else {
                    return
                }
                apply(
                    holidayState: .unavailable,
                    personalSnapshot: personalSnapshot,
                    scheduleSnapshot: scheduleSnapshot,
                    dateKnowledgeSnapshot: knowledgeSnapshot
                )
                await systemCalendarTask
            }
        } catch {
            guard !hasVisibleContent else {
                errorMessage = "刷新失败，继续显示上次有效数据"
                dataState = .refreshFailed
                return
            }

            errorMessage = "节假日数据暂不可用"
            apply(
                holidayState: .unavailable,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: nil
            )

            let knowledgeSnapshot = await knowledgeTask
            guard let knowledgeSnapshot else {
                return
            }
            apply(
                holidayState: .unavailable,
                personalSnapshot: personalSnapshot,
                scheduleSnapshot: scheduleSnapshot,
                dateKnowledgeSnapshot: knowledgeSnapshot
            )
            await systemCalendarTask
        }
    }

    func loadSystemCalendarEvents() async {
        guard let systemCalendarService else {
            systemCalendarAccess = .unavailable
            systemCalendarState = .unavailable
            systemCalendarEvents = []
            systemCalendarErrorMessage = nil
            return
        }

        let access = systemCalendarService.access
        systemCalendarAccess = access
        systemCalendarErrorMessage = nil

        switch access {
        case .fullAccess:
            break
        case .notDetermined:
            systemCalendarEvents = []
            systemCalendarState = .permissionRequired
            return
        case .denied, .writeOnly:
            systemCalendarEvents = []
            systemCalendarState = .accessDenied
            return
        case .restricted:
            systemCalendarEvents = []
            systemCalendarState = .accessRestricted
            return
        case .unavailable:
            systemCalendarEvents = []
            systemCalendarState = .unavailable
            return
        }

        do {
            selectedSystemCalendarIDs = try systemCalendarSelectionStore?.selectedCalendarIDs()
        } catch {
            selectedSystemCalendarIDs = nil
            systemCalendarErrorMessage = "系统日历来源设置读取失败，暂显示全部来源"
        }

        if selectedSystemCalendarIDs?.isEmpty == true {
            systemCalendarEvents = []
            systemCalendarState = .filteredOut
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        guard let startDate = dayID.date,
              let endDate = calendar.date(
                  byAdding: .day,
                  value: 1,
                  to: startDate
              ) else {
            systemCalendarEvents = []
            systemCalendarState = .failed
            systemCalendarErrorMessage = "无法生成系统日历查询日期范围"
            return
        }

        systemCalendarState = .loading

        do {
            systemCalendarEvents = try await systemCalendarService.events(
                in: DateInterval(start: startDate, end: endDate),
                calendarIDs: selectedSystemCalendarIDs
            )
            systemCalendarState = .loaded
        } catch is CancellationError {
            return
        } catch let error as SystemCalendarServiceError {
            systemCalendarEvents = []
            systemCalendarErrorMessage = error.localizedDescription
            systemCalendarState = error == .accessRestricted
                ? .accessRestricted
                : error == .permissionDenied ? .accessDenied : .failed
        } catch {
            systemCalendarEvents = []
            systemCalendarErrorMessage = "系统日历读取失败"
            systemCalendarState = .failed
        }
    }

    func observeSystemCalendarChanges() async {
        guard let systemCalendarService else {
            return
        }

        for await _ in systemCalendarService.changes() {
            guard !Task.isCancelled else {
                return
            }
            await loadSystemCalendarEvents()
        }
    }

    private func apply(
        holidayState: HolidayYearRefreshState,
        personalSnapshot: PersonalDateSnapshot?,
        scheduleSnapshot: ScheduleSnapshot?,
        dateKnowledgeSnapshot: DateKnowledgeYearSnapshot?
    ) {
        presentation = compositionService.compose(
            dayID: dayID,
            holidayState: holidayState,
            vacationPeriods: personalSnapshot?.vacationPeriods ?? [],
            specialDays: personalSnapshot?.specialDays ?? [],
            schedules: scheduleSnapshot?.items ?? [],
            dateKnowledgeSnapshot: dateKnowledgeSnapshot
        )
        scheduleItems = (scheduleSnapshot?.items ?? []).filter { $0.occurs(on: dayID) }
            .sorted { $0.startDate < $1.startDate }

        switch holidayState {
        case let .available(snapshot):
            dataState = .loaded
            sourceURL = snapshot.sourceURL
            fetchedAt = snapshot.fetchedAt
        case .notPublished:
            dataState = .notPublished
            sourceURL = nil
            fetchedAt = nil
        case .unavailable:
            dataState = .unavailable
            sourceURL = nil
            fetchedAt = nil
        }

        dateKnowledgeProviderID = dateKnowledgeSnapshot?.providerID
        dateKnowledgeSourceURL = dateKnowledgeSnapshot?.sourceURL
        dateKnowledgeFetchedAt = dateKnowledgeSnapshot?.fetchedAt
    }

    private func personalDateSnapshot() -> PersonalDateSnapshot? {
        guard let vacationRepository else {
            return nil
        }

        return try? vacationRepository.snapshot(for: dayID.year)
    }

    private func scheduleSnapshot() -> ScheduleSnapshot? {
        guard let scheduleRepository else {
            return nil
        }

        return try? scheduleRepository.snapshot(for: dayID.year)
    }

    private func dateKnowledgeSnapshot() async -> DateKnowledgeYearSnapshot? {
        guard let dateKnowledgeRepository else {
            return nil
        }

        return try? await dateKnowledgeRepository.snapshot(for: dayID.year)
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
}
