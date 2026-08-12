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

enum SystemCalendarChange: Equatable, Sendable {
    case storeChanged
}

enum SystemCalendarEventDraftValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyTitle
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "系统事件标题不能为空"
        case .invalidDateRange:
            "系统事件结束时间不能早于开始时间"
        }
    }
}

struct SystemCalendarEventDraft: Equatable, Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let note: String?

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        note: String? = nil
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw SystemCalendarEventDraftValidationError.emptyTitle
        }
        guard startDate <= endDate else {
            throw SystemCalendarEventDraftValidationError.invalidDateRange
        }

        self.title = normalizedTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SystemCalendarWriteError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case accessRestricted
    case unavailable
    case noWritableCalendar
    case calendarNotFound
    case calendarNotWritable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有系统日历写入权限"
        case .accessRestricted:
            "系统日历访问受限"
        case .unavailable:
            "系统日历服务不可用"
        case .noWritableCalendar:
            "没有可写入的系统日历"
        case .calendarNotFound:
            "目标系统日历不存在"
        case .calendarNotWritable:
            "目标系统日历不允许写入"
        case .saveFailed:
            "系统事件保存失败"
        }
    }
}

struct SystemCalendarDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let identifier: String
    let title: String
    let sourceTitle: String?

    var id: String {
        identifier
    }

    init(identifier: String, title: String, sourceTitle: String? = nil) {
        self.identifier = identifier
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle.isEmpty ? "未命名日历" : trimmedTitle
        self.sourceTitle = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displaySourceTitle: String {
        guard let sourceTitle, !sourceTitle.isEmpty else {
            return "本机日历"
        }
        return sourceTitle
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
