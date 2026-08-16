import Foundation
import Observation

enum SettingsSystemCalendarState: Equatable, Sendable {
    case idle
    case requesting
    case loading
    case ready
    case unavailable
    case failed
}

enum SettingsNotificationState: Equatable, Sendable {
    case idle
    case requesting
    case ready
    case unavailable
    case failed
}

enum SettingsNotificationPlanState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

@MainActor
@Observable
final class SettingsFeatureModel {
    @ObservationIgnored let holidayRepository: (any HolidayRepositoryProtocol)?
    @ObservationIgnored let vacationRepository: (any VacationRepositoryProtocol)?
    @ObservationIgnored let scheduleRepository: (any ScheduleRepositoryProtocol)?
    @ObservationIgnored let dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)?
    @ObservationIgnored let systemCalendarService: (any SystemCalendarServiceProtocol)?
    @ObservationIgnored let systemCalendarSelectionStore: (any SystemCalendarSelectionStoreProtocol)?
    @ObservationIgnored let notificationService: (any NotificationServiceProtocol)?
    @ObservationIgnored let notificationPreferencesStore: (any NotificationPreferencesStoreProtocol)?

    var systemCalendarAccess: SystemCalendarAccess
    var systemCalendarState: SettingsSystemCalendarState = .idle
    var systemCalendarCalendars: [SystemCalendarDescriptor] = []
    var selectedSystemCalendarIDs: Set<String> = []
    var isSystemCalendarSelectionConfigured = false
    var errorMessage: String?
    var notificationAuthorization: CalendarNotificationAuthorization
    var notificationState: SettingsNotificationState
    var notificationErrorMessage: String?
    var notificationPreferences: CalendarNotificationPreferences = .disabled
    var notificationPlanState: SettingsNotificationPlanState = .idle
    var notificationPlanCount = 0
    var dateKnowledgeState: DateKnowledgeLoadState = .idle
    var dateKnowledgeDiagnostics: [DateKnowledgeSourceDiagnostic] = []
    var dateKnowledgeYear = DayID(Date()).year
    var dateKnowledgeErrorMessage: String?

    init(
        systemCalendarService: (any SystemCalendarServiceProtocol)?,
        systemCalendarSelectionStore: (any SystemCalendarSelectionStoreProtocol)? = nil,
        notificationService: (any NotificationServiceProtocol)? = nil,
        holidayRepository: (any HolidayRepositoryProtocol)? = nil,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        notificationPreferencesStore: (any NotificationPreferencesStoreProtocol)? = nil
    ) {
        self.holidayRepository = holidayRepository
        self.vacationRepository = vacationRepository
        self.scheduleRepository = scheduleRepository
        self.dateKnowledgeRepository = dateKnowledgeRepository
        self.systemCalendarService = systemCalendarService
        self.systemCalendarSelectionStore = systemCalendarSelectionStore
        self.notificationService = notificationService
        self.notificationPreferencesStore = notificationPreferencesStore
        self.systemCalendarAccess = systemCalendarService?.access ?? .unavailable
        self.notificationAuthorization = notificationService == nil ? .unavailable : .notDetermined
        self.notificationState = notificationService == nil ? .unavailable : .idle
    }

    func loadDateKnowledgeDiagnostics(referenceDate: Date = Date()) async {
        guard let dateKnowledgeRepository else {
            dateKnowledgeState = .unavailable
            dateKnowledgeDiagnostics = []
            dateKnowledgeErrorMessage = "日期知识服务尚未准备好"
            return
        }

        dateKnowledgeYear = DayID(referenceDate).year
        dateKnowledgeErrorMessage = nil
        dateKnowledgeState = .loading

        do {
            _ = try await dateKnowledgeRepository.snapshot(for: dateKnowledgeYear)
            dateKnowledgeState = dateKnowledgeRepository.lastLoadState
            dateKnowledgeDiagnostics = dateKnowledgeRepository.sourceDiagnostics
            if dateKnowledgeState == .unavailable {
                dateKnowledgeErrorMessage = "日期知识数据暂不可用"
            }
        } catch is CancellationError {
            dateKnowledgeState = .idle
        } catch let error as LocalizedError {
            dateKnowledgeState = .unavailable
            dateKnowledgeDiagnostics = dateKnowledgeRepository.sourceDiagnostics
            dateKnowledgeErrorMessage = error.errorDescription ?? "日期知识数据读取失败"
        } catch {
            dateKnowledgeState = .unavailable
            dateKnowledgeDiagnostics = dateKnowledgeRepository.sourceDiagnostics
            dateKnowledgeErrorMessage = "日期知识数据读取失败"
        }
    }

    func loadNotificationAuthorization() async {
        guard let notificationService else {
            notificationAuthorization = .unavailable
            notificationState = .unavailable
            return
        }

        notificationErrorMessage = nil
        notificationAuthorization = await notificationService.authorizationStatus()
        notificationState = .ready
    }

    func loadNotificationPreferences() {
        guard let notificationPreferencesStore else {
            return
        }

        do {
            notificationPreferences = try notificationPreferencesStore.load() ?? .disabled
            notificationPlanState = .idle
            notificationPlanCount = 0
            notificationErrorMessage = nil
        } catch let error as LocalizedError {
            notificationPreferences = .disabled
            notificationPlanState = .failed
            notificationPlanCount = 0
            notificationErrorMessage = error.errorDescription ?? "通知规则设置无法读取"
        } catch {
            notificationPreferences = .disabled
            notificationPlanState = .failed
            notificationPlanCount = 0
            notificationErrorMessage = "通知规则设置无法读取"
        }
    }

    func setNotificationKindEnabled(
        _ enabled: Bool,
        for kind: CalendarNotificationKind
    ) {
        let previousPreferences = notificationPreferences
        notificationPreferences.setEnabled(enabled, for: kind)
        notificationPlanState = .idle
        notificationPlanCount = 0

        do {
            try notificationPreferencesStore?.save(notificationPreferences)
            notificationErrorMessage = nil
        } catch let error as LocalizedError {
            notificationPreferences = previousPreferences
            notificationErrorMessage = error.errorDescription ?? "通知规则设置无法保存"
        } catch {
            notificationPreferences = previousPreferences
            notificationErrorMessage = "通知规则设置无法保存"
        }
    }

    func reconcileNotificationPlan(referenceDate: Date = Date()) async {
        guard let notificationService else {
            notificationPlanState = .failed
            notificationErrorMessage = "通知服务尚未准备好"
            return
        }

        guard notificationAuthorization.canSchedule else {
            notificationPlanState = .failed
            notificationErrorMessage = notificationAuthorization == .unavailable
                ? CalendarNotificationServiceError.unavailable.errorDescription
                : CalendarNotificationServiceError.permissionDenied.errorDescription
            return
        }

        notificationErrorMessage = nil
        notificationPlanState = .loading

        do {
            let year = DayID(referenceDate).year
            var schedules: [ScheduleItem] = []
            var holidayRecords: [HolidayRecord] = []
            var specialDays: [SpecialDay] = []

            if notificationPreferences.isEnabled(.schedule),
               let scheduleRepository {
                schedules = try scheduleRepository.snapshot(for: year).items
            }

            if (notificationPreferences.isEnabled(.holiday)
                || notificationPreferences.isEnabled(.makeupWorkday)),
               let holidayRepository {
                holidayRecords = try await holidayRepository.snapshot(for: year).records
            }

            if notificationPreferences.isEnabled(.specialDay),
               let vacationRepository {
                specialDays = try vacationRepository.snapshot(for: year).specialDays
            }

            let requests = try CalendarNotificationPlanBuilder().build(
                schedules: schedules,
                holidayRecords: holidayRecords,
                specialDays: specialDays,
                preferences: notificationPreferences,
                referenceDate: referenceDate
            )
            try await notificationService.reconcile(requests)
            notificationPlanCount = requests.count
            notificationPlanState = .ready
        } catch is CancellationError {
            notificationPlanState = .idle
        } catch let error as LocalizedError {
            notificationPlanState = .failed
            notificationErrorMessage = error.errorDescription ?? "通知计划同步失败"
        } catch {
            notificationPlanState = .failed
            notificationErrorMessage = "通知计划同步失败"
        }
    }

    var notificationPlanSummary: String {
        guard notificationPlanState == .ready else {
            return "尚未同步提醒计划"
        }
        return "当前有 \(notificationPlanCount) 条待发送提醒"
    }

    func requestNotificationAuthorization() async {
        guard let notificationService else {
            notificationAuthorization = .unavailable
            notificationState = .unavailable
            notificationErrorMessage = "通知服务尚未准备好"
            return
        }

        notificationErrorMessage = nil
        notificationState = .requesting
        notificationAuthorization = await notificationService.requestAuthorization()
        notificationState = .ready
    }

    func reconcileNotifications(_ requests: [CalendarNotificationRequest]) async {
        guard let notificationService else {
            notificationAuthorization = .unavailable
            notificationState = .unavailable
            notificationErrorMessage = "通知服务尚未准备好"
            return
        }

        guard notificationAuthorization.canSchedule else {
            notificationErrorMessage = notificationAuthorization == .unavailable
                ? CalendarNotificationServiceError.unavailable.errorDescription
                : CalendarNotificationServiceError.permissionDenied.errorDescription
            return
        }

        do {
            try await notificationService.reconcile(requests)
            notificationErrorMessage = nil
        } catch let error as LocalizedError {
            notificationErrorMessage = error.errorDescription ?? "通知安排失败"
        } catch {
            notificationErrorMessage = "通知安排失败"
        }
    }

    func refreshSystemCalendarAccess() {
        guard let systemCalendarService else {
            systemCalendarAccess = .unavailable
            systemCalendarState = .unavailable
            systemCalendarCalendars = []
            selectedSystemCalendarIDs = []
            isSystemCalendarSelectionConfigured = false
            return
        }

        systemCalendarAccess = systemCalendarService.access
        if systemCalendarAccess != .fullAccess {
            systemCalendarCalendars = []
            selectedSystemCalendarIDs = []
            isSystemCalendarSelectionConfigured = false
        }
        systemCalendarState = .ready
    }

    func loadSystemCalendarConfiguration() async {
        guard let systemCalendarService else {
            refreshSystemCalendarAccess()
            return
        }

        refreshSystemCalendarAccess()
        guard systemCalendarAccess == .fullAccess else {
            return
        }

        errorMessage = nil
        systemCalendarState = .loading

        do {
            let calendars = try await systemCalendarService.calendars()
            systemCalendarCalendars = calendars
            let availableIDs = Set(calendars.map(\.identifier))

            do {
                if let savedIDs = try systemCalendarSelectionStore?.selectedCalendarIDs() {
                    selectedSystemCalendarIDs = savedIDs.intersection(availableIDs)
                    isSystemCalendarSelectionConfigured = true
                } else {
                    selectedSystemCalendarIDs = availableIDs
                    isSystemCalendarSelectionConfigured = false
                }
            } catch {
                selectedSystemCalendarIDs = availableIDs
                isSystemCalendarSelectionConfigured = false
                errorMessage = "来源设置读取失败，暂显示全部系统日历"
            }
            systemCalendarState = .ready
        } catch is CancellationError {
            return
        } catch let error as LocalizedError {
            systemCalendarCalendars = []
            selectedSystemCalendarIDs = []
            systemCalendarState = .failed
            errorMessage = error.errorDescription ?? "系统日历来源读取失败"
        } catch {
            systemCalendarCalendars = []
            selectedSystemCalendarIDs = []
            systemCalendarState = .failed
            errorMessage = "系统日历来源读取失败"
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
            await loadSystemCalendarConfiguration()
        }
    }

    func requestSystemCalendarReadAccess() async {
        guard let systemCalendarService else {
            systemCalendarAccess = .unavailable
            systemCalendarState = .unavailable
            errorMessage = "系统日历服务尚未准备好"
            return
        }

        errorMessage = nil
        systemCalendarState = .requesting
        systemCalendarAccess = await systemCalendarService.requestReadAccess()

        if systemCalendarAccess == .fullAccess {
            await loadSystemCalendarConfiguration()
        } else {
            systemCalendarState = .ready
        }
    }

    func isSystemCalendarSelected(_ identifier: String) -> Bool {
        !isSystemCalendarSelectionConfigured || selectedSystemCalendarIDs.contains(identifier)
    }

    func setSystemCalendarSelected(_ selected: Bool, for identifier: String) {
        let previousIDs = selectedSystemCalendarIDs
        let previousConfiguration = isSystemCalendarSelectionConfigured

        if !isSystemCalendarSelectionConfigured {
            isSystemCalendarSelectionConfigured = true
            selectedSystemCalendarIDs = Set(systemCalendarCalendars.map(\.identifier))
        }

        if selected {
            selectedSystemCalendarIDs.insert(identifier)
        } else {
            selectedSystemCalendarIDs.remove(identifier)
        }

        do {
            try systemCalendarSelectionStore?.save(selectedCalendarIDs: selectedSystemCalendarIDs)
            errorMessage = nil
        } catch let error as LocalizedError {
            selectedSystemCalendarIDs = previousIDs
            isSystemCalendarSelectionConfigured = previousConfiguration
            errorMessage = error.errorDescription ?? "系统日历来源设置无法保存"
        } catch {
            selectedSystemCalendarIDs = previousIDs
            isSystemCalendarSelectionConfigured = previousConfiguration
            errorMessage = "系统日历来源设置无法保存"
        }
    }

    func selectAllSystemCalendars() {
        let allIDs = Set(systemCalendarCalendars.map(\.identifier))
        selectedSystemCalendarIDs = allIDs
        isSystemCalendarSelectionConfigured = true

        do {
            try systemCalendarSelectionStore?.save(selectedCalendarIDs: allIDs)
            errorMessage = nil
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "系统日历来源设置无法保存"
        } catch {
            errorMessage = "系统日历来源设置无法保存"
        }
    }

    var systemCalendarSelectionSummary: String {
        guard !systemCalendarCalendars.isEmpty else {
            return "暂无可用日历来源"
        }

        if !isSystemCalendarSelectionConfigured
            || selectedSystemCalendarIDs.count == systemCalendarCalendars.count {
            return "显示全部 \(systemCalendarCalendars.count) 个日历"
        }

        if selectedSystemCalendarIDs.isEmpty {
            return "未选择任何日历来源"
        }

        return "已选择 \(selectedSystemCalendarIDs.count) 个日历来源"
    }
}
