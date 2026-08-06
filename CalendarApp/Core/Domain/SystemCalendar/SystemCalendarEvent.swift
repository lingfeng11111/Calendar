import Foundation

enum SystemCalendarAccess: String, Codable, CaseIterable, Equatable, Sendable {
    case unavailable
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess

    var canRead: Bool {
        self == .fullAccess
    }

    var displayName: String {
        switch self {
        case .unavailable:
            "系统日历服务不可用"
        case .notDetermined:
            "尚未请求访问"
        case .restricted:
            "访问受限"
        case .denied:
            "访问已拒绝"
        case .writeOnly:
            "仅允许写入"
        case .fullAccess:
            "已允许读取"
        }
    }
}

enum SystemCalendarServiceError: Error, Equatable, LocalizedError, Sendable {
    case invalidDateRange
    case permissionDenied
    case accessRestricted
    case readFailed

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            "系统日历查询日期范围无效"
        case .permissionDenied:
            "系统日历读取权限未开启"
        case .accessRestricted:
            "系统日历访问受到限制"
        case .readFailed:
            "系统日历读取失败"
        }
    }
}

struct SystemCalendarEventSnapshot: Codable, Equatable, Hashable, Identifiable, Sendable {
    let externalIdentifier: String
    let calendarItemIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let sourceTitle: String?
    let recurrenceDescription: String?
    let note: String?

    var id: String {
        "\(externalIdentifier)|\(Int64(startDate.timeIntervalSince1970 * 1_000))"
    }

    init(
        externalIdentifier: String,
        calendarItemIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String?,
        calendarIdentifier: String,
        calendarTitle: String,
        sourceTitle: String? = nil,
        recurrenceDescription: String? = nil,
        note: String? = nil
    ) {
        self.externalIdentifier = externalIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.sourceTitle = sourceTitle
        self.recurrenceDescription = recurrenceDescription
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
