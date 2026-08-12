import Foundation

enum CalendarNotificationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case schedule
    case holiday
    case makeupWorkday
    case specialDay

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .schedule:
            "日程"
        case .holiday:
            "节假日"
        case .makeupWorkday:
            "调休补班"
        case .specialDay:
            "纪念日"
        }
    }
}

enum CalendarNotificationAuthorization: String, Codable, CaseIterable, Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .unavailable, .notDetermined, .denied:
            false
        }
    }

    var displayName: String {
        switch self {
        case .unavailable:
            "通知服务不可用"
        case .notDetermined:
            "尚未请求通知权限"
        case .denied:
            "通知已关闭"
        case .authorized:
            "通知已允许"
        case .provisional:
            "通知已临时允许"
        case .ephemeral:
            "通知已临时授权"
        }
    }
}

enum CalendarNotificationRequestValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyIdentifier
    case emptyTitle
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            "通知标识不能为空"
        case .emptyTitle:
            "通知标题不能为空"
        case .invalidDate:
            "通知日期无效"
        }
    }
}

struct CalendarNotificationRequest: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: CalendarNotificationKind
    let title: String
    let body: String
    let date: Date

    init(
        id: String,
        kind: CalendarNotificationKind,
        title: String,
        body: String,
        date: Date
    ) throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw CalendarNotificationRequestValidationError.emptyIdentifier
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw CalendarNotificationRequestValidationError.emptyTitle
        }

        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw CalendarNotificationRequestValidationError.invalidDate
        }

        self.id = normalizedID
        self.kind = kind
        self.title = normalizedTitle
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
    }
}

enum CalendarNotificationServiceError: Error, Equatable, LocalizedError, Sendable {
    case unavailable
    case permissionDenied
    case schedulingFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "通知服务不可用"
        case .permissionDenied:
            "没有通知权限"
        case .schedulingFailed:
            "通知安排失败"
        }
    }
}

enum CalendarNotificationPreferencesValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidScheduleLeadTime
    case invalidDayTriggerHour
    case invalidDayTriggerMinute

    var errorDescription: String? {
        switch self {
        case .invalidScheduleLeadTime:
            "日程提醒提前时间无效"
        case .invalidDayTriggerHour:
            "全天提醒小时无效"
        case .invalidDayTriggerMinute:
            "全天提醒分钟无效"
        }
    }
}

struct CalendarNotificationPreferences: Codable, Equatable, Sendable {
    var enabledKinds: Set<CalendarNotificationKind>
    var scheduleLeadTimeMinutes: Int
    var dayTriggerHour: Int
    var dayTriggerMinute: Int

    init(
        enabledKinds: Set<CalendarNotificationKind> = [],
        scheduleLeadTimeMinutes: Int = 15,
        dayTriggerHour: Int = 9,
        dayTriggerMinute: Int = 0
    ) throws {
        guard (0...24 * 60).contains(scheduleLeadTimeMinutes) else {
            throw CalendarNotificationPreferencesValidationError.invalidScheduleLeadTime
        }
        guard (0...23).contains(dayTriggerHour) else {
            throw CalendarNotificationPreferencesValidationError.invalidDayTriggerHour
        }
        guard (0...59).contains(dayTriggerMinute) else {
            throw CalendarNotificationPreferencesValidationError.invalidDayTriggerMinute
        }

        self.enabledKinds = enabledKinds
        self.scheduleLeadTimeMinutes = scheduleLeadTimeMinutes
        self.dayTriggerHour = dayTriggerHour
        self.dayTriggerMinute = dayTriggerMinute
    }

    static var disabled: Self {
        try! Self()
    }

    func isEnabled(_ kind: CalendarNotificationKind) -> Bool {
        enabledKinds.contains(kind)
    }

    mutating func setEnabled(_ enabled: Bool, for kind: CalendarNotificationKind) {
        if enabled {
            enabledKinds.insert(kind)
        } else {
            enabledKinds.remove(kind)
        }
    }
}

enum CalendarNotificationPlanError: Error, Equatable, LocalizedError, Sendable {
    case invalidHorizon
    case invalidRequest(CalendarNotificationRequestValidationError)

    var errorDescription: String? {
        switch self {
        case .invalidHorizon:
            "通知计划时间范围无效"
        case let .invalidRequest(error):
            error.errorDescription ?? "通知计划请求无效"
        }
    }
}
