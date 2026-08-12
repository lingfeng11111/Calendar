import Foundation

struct CalendarWidgetNextDate: Codable, Equatable, Sendable {
    let dayID: String
    let dateLabel: String
    let title: String
    let subtitle: String?
}

struct CalendarWidgetSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.lingfeng.CalendarApp"
    static let widgetKind = "CalendarApp.TodayWidget"
    static let referenceTimeZoneIdentifier = "Asia/Shanghai"

    static var referenceTimeZone: TimeZone {
        TimeZone(identifier: referenceTimeZoneIdentifier) ?? .gmt
    }

    let schemaVersion: Int
    let generatedAt: Date
    let dayID: String
    let dateLabel: String
    let statusKey: String
    let statusLabel: String
    let statusReason: String?
    let primaryTitle: String?
    let primaryKind: String?
    let scheduleCount: Int
    let vacationLabels: [String]
    let specialDayLabels: [String]
    let nextDate: CalendarWidgetNextDate?

    init(
        generatedAt: Date,
        dayID: String,
        dateLabel: String,
        statusKey: String,
        statusLabel: String,
        statusReason: String? = nil,
        primaryTitle: String? = nil,
        primaryKind: String? = nil,
        scheduleCount: Int = 0,
        vacationLabels: [String] = [],
        specialDayLabels: [String] = [],
        nextDate: CalendarWidgetNextDate? = nil,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dayID = dayID
        self.dateLabel = dateLabel
        self.statusKey = statusKey
        self.statusLabel = statusLabel
        self.statusReason = statusReason
        self.primaryTitle = primaryTitle
        self.primaryKind = primaryKind
        self.scheduleCount = max(0, scheduleCount)
        self.vacationLabels = vacationLabels
        self.specialDayLabels = specialDayLabels
        self.nextDate = nextDate
    }

    static let placeholder = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        dayID: "—",
        dateLabel: "等待更新",
        statusKey: "unknown",
        statusLabel: "待更新",
        primaryTitle: "打开 CalendarApp 刷新数据"
    )
}

struct CalendarWidgetTimelinePolicy: Equatable, Sendable {
    static let defaultRefreshInterval: TimeInterval = 60 * 60

    let refreshInterval: TimeInterval
    let timeZoneIdentifier: String

    init(
        refreshInterval: TimeInterval = Self.defaultRefreshInterval,
        timeZoneIdentifier: String = CalendarWidgetSnapshot.referenceTimeZoneIdentifier
    ) {
        self.refreshInterval = max(60, refreshInterval)
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func nextRefresh(
        after date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)
            ?? CalendarWidgetSnapshot.referenceTimeZone
        let seconds = Int(refreshInterval.rounded())
        return calendar.date(byAdding: .second, value: seconds, to: date)
            ?? date.addingTimeInterval(refreshInterval)
    }
}
