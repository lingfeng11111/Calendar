import Foundation

enum ScheduleColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case teal
    case purple
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue:
            "蓝色"
        case .teal:
            "青绿色"
        case .purple:
            "紫色"
        case .orange:
            "橙色"
        }
    }
}

enum ScheduleRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            "不重复"
        case .daily:
            "每天"
        case .weekly:
            "每周"
        }
    }
}

enum ScheduleKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case allDay
    case timed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            "全部类型"
        case .allDay:
            "全天"
        case .timed:
            "定时"
        }
    }
}

struct ScheduleQuery: Equatable, Sendable {
    var text: String = ""
    var kind: ScheduleKindFilter = .all
    var color: ScheduleColor?
    var startDay: DayID?
    var endDay: DayID?

    func matches(_ schedule: ScheduleItem) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedText.isEmpty {
            let titleMatches = schedule.title.localizedCaseInsensitiveContains(normalizedText)
            let noteMatches = schedule.note?.localizedCaseInsensitiveContains(normalizedText) == true
            guard titleMatches || noteMatches else {
                return false
            }
        }

        switch kind {
        case .all:
            break
        case .allDay where !schedule.isAllDay:
            return false
        case .timed where schedule.isAllDay:
            return false
        default:
            break
        }

        if let color, schedule.color != color {
            return false
        }

        if let startDay, let endDay {
            let lowerBound = min(startDay, endDay)
            let upperBound = max(startDay, endDay)
            let scheduleEnd = schedule.coverageEndDay
            guard schedule.startDay <= upperBound, lowerBound <= scheduleEnd else {
                return false
            }
        }

        return true
    }
}

enum ScheduleItemValidationError: Error, Equatable, Sendable, LocalizedError {
    case emptyTitle
    case invalidRange
    case missingRepeatEnd
    case invalidRepeatRange

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "日程标题不能为空"
        case .invalidRange:
            "结束时间不能早于开始时间"
        case .missingRepeatEnd:
            "重复日程需要设置结束日期"
        case .invalidRepeatRange:
            "重复结束日期不能早于日程结束日期"
        }
    }
}

struct ScheduleItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrence: ScheduleRecurrence
    var repeatUntil: Date?
    var color: ScheduleColor
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        recurrence: ScheduleRecurrence = .none,
        repeatUntil: Date? = nil,
        color: ScheduleColor = .blue,
        note: String? = nil
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ScheduleItemValidationError.emptyTitle
        }
        guard startDate <= endDate else {
            throw ScheduleItemValidationError.invalidRange
        }

        if recurrence != .none {
            guard let repeatUntil else {
                throw ScheduleItemValidationError.missingRepeatEnd
            }
            guard repeatUntil >= endDate else {
                throw ScheduleItemValidationError.invalidRepeatRange
            }
        }

        self.id = id
        self.title = normalizedTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.repeatUntil = recurrence == .none ? nil : repeatUntil
        self.color = color
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var startDay: DayID {
        DayID(startDate)
    }

    var endDay: DayID {
        DayID(endDate)
    }

    var repeatUntilDay: DayID? {
        repeatUntil.map { DayID($0) }
    }

    var dayCount: Int {
        startDay.days(to: endDay) + 1
    }

    var coverageEndDay: DayID {
        guard recurrence != .none, let repeatUntilDay else {
            return endDay
        }

        return repeatUntilDay.adding(days: max(0, dayCount - 1))
    }

    func occurs(on dayID: DayID) -> Bool {
        switch recurrence {
        case .none:
            return startDay <= dayID && dayID <= endDay
        case .daily:
            guard repeatUntil != nil else {
                return false
            }
            return startDay <= dayID && dayID <= coverageEndDay
        case .weekly:
            guard let repeatUntilDay else {
                return false
            }
            guard startDay <= dayID, dayID <= coverageEndDay else {
                return false
            }

            let durationDays = max(0, dayCount - 1)
            for offset in 0...durationDays {
                let occurrenceStart = dayID.adding(days: -offset)
                guard startDay <= occurrenceStart, occurrenceStart <= repeatUntilDay else {
                    continue
                }

                if startDay.days(to: occurrenceStart).isMultiple(of: 7) {
                    return true
                }
            }

            return false
        }
    }

    func overlaps(year: Int) -> Bool {
        guard let yearStart = DayID(year: year, month: 1, day: 1),
              let yearEnd = DayID(year: year, month: 12, day: 31) else {
            return false
        }

        switch recurrence {
        case .none:
            return startDay <= yearEnd && yearStart <= endDay
        case .daily, .weekly:
            guard repeatUntil != nil else {
                return false
            }
            return startDay <= yearEnd && yearStart <= coverageEndDay
        }
    }
}
