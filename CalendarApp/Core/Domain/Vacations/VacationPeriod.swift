import Foundation

enum VacationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case winter
    case summer
    case annualLeave
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .winter:
            "寒假"
        case .summer:
            "暑假"
        case .annualLeave:
            "年假"
        case .custom:
            "自定义假期"
        }
    }

    var systemImage: String {
        switch self {
        case .winter:
            "snowflake"
        case .summer:
            "sun.max"
        case .annualLeave:
            "airplane"
        case .custom:
            "calendar.badge.plus"
        }
    }
}

enum VacationPeriodValidationError: Error, Equatable, Sendable, LocalizedError {
    case emptyTitle
    case invalidRange
    case mismatchedCalendar

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "假期名称不能为空"
        case .invalidRange:
            "假期结束日期不能早于开始日期"
        case .mismatchedCalendar:
            "假期日期必须使用同一日历和时区"
        }
    }
}

struct VacationPeriod: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var kind: VacationKind
    var startDay: DayID
    var endDay: DayID
    var color: PersonalDateColor
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        kind: VacationKind,
        startDay: DayID,
        endDay: DayID,
        color: PersonalDateColor = .teal,
        note: String? = nil
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw VacationPeriodValidationError.emptyTitle
        }
        guard startDay.calendarIdentifier == endDay.calendarIdentifier,
              startDay.timeZoneIdentifier == endDay.timeZoneIdentifier else {
            throw VacationPeriodValidationError.mismatchedCalendar
        }
        guard startDay <= endDay else {
            throw VacationPeriodValidationError.invalidRange
        }

        self.id = id
        self.title = normalizedTitle
        self.kind = kind
        self.startDay = startDay
        self.endDay = endDay
        self.color = color
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dayCount: Int {
        startDay.days(to: endDay) + 1
    }

    func contains(_ dayID: DayID) -> Bool {
        guard dayID.calendarIdentifier == startDay.calendarIdentifier,
              dayID.timeZoneIdentifier == startDay.timeZoneIdentifier else {
            return false
        }

        return startDay <= dayID && dayID <= endDay
    }

    func overlaps(year: Int) -> Bool {
        startDay.year <= year && year <= endDay.year
    }
}
