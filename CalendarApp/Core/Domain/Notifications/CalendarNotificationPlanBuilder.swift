import Foundation

struct CalendarNotificationPlanBuilder {
    private var calendar: Calendar

    init(calendar: Calendar = Self.defaultCalendar) {
        var calendar = calendar
        calendar.timeZone = DayID.defaultTimeZone
        self.calendar = calendar
    }

    func build(
        schedules: [ScheduleItem],
        holidayRecords: [HolidayRecord],
        specialDays: [SpecialDay],
        preferences: CalendarNotificationPreferences,
        referenceDate: Date,
        horizonDays: Int = 365
    ) throws -> [CalendarNotificationRequest] {
        guard horizonDays >= 0,
              let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: referenceDate) else {
            throw CalendarNotificationPlanError.invalidHorizon
        }

        var requestsByID: [String: CalendarNotificationRequest] = [:]

        if preferences.isEnabled(.schedule) {
            for schedule in schedules {
                for occurrenceStart in occurrenceStarts(
                    for: schedule,
                    referenceDate: referenceDate,
                    horizonEnd: horizonEnd
                ) {
                    let triggerDate: Date
                    if schedule.isAllDay {
                        let day = DayID(occurrenceStart)
                        guard let allDayTrigger = dayTriggerDate(for: day, preferences: preferences) else {
                            continue
                        }
                        triggerDate = allDayTrigger
                    } else {
                        triggerDate = occurrenceStart.addingTimeInterval(
                            -TimeInterval(preferences.scheduleLeadTimeMinutes * 60)
                        )
                    }

                    guard isInRange(triggerDate, referenceDate: referenceDate, horizonEnd: horizonEnd) else {
                        continue
                    }

                    let dayID = DayID(occurrenceStart)
                    let body = schedule.isAllDay
                        ? "今天有日程：\(schedule.title)"
                        : "日程将在 \(timeDescription(for: occurrenceStart)) 开始"
                    let request = try makeRequest(
                        id: "schedule.\(schedule.id.uuidString).\(dayID.description)",
                        kind: .schedule,
                        title: schedule.title,
                        body: body,
                        date: triggerDate
                    )
                    requestsByID[request.id] = request
                }
            }
        }

        for record in holidayRecords {
            let kind: CalendarNotificationKind = record.kind == .holiday
                ? .holiday
                : .makeupWorkday
            guard preferences.isEnabled(kind),
                  let triggerDate = dayTriggerDate(for: record.dayID, preferences: preferences),
                  isInRange(triggerDate, referenceDate: referenceDate, horizonEnd: horizonEnd) else {
                continue
            }

            let body = record.kind == .holiday
                ? "今天是法定节假日"
                : "今天按工作日安排"
            let request = try makeRequest(
                id: "\(kind.rawValue).\(record.dayID.description)",
                kind: kind,
                title: record.name,
                body: body,
                date: triggerDate
            )
            requestsByID[request.id] = request
        }

        if preferences.isEnabled(.specialDay) {
            let firstYear = DayID(referenceDate).year
            let lastYear = DayID(horizonEnd).year
            for specialDay in specialDays {
                for year in firstYear...lastYear {
                    guard let day = specialDay.resolvedDay(for: year),
                          let triggerDate = dayTriggerDate(for: day, preferences: preferences),
                          isInRange(triggerDate, referenceDate: referenceDate, horizonEnd: horizonEnd) else {
                        continue
                    }

                    let request = try makeRequest(
                        id: "special-day.\(specialDay.id.uuidString).\(day.description)",
                        kind: .specialDay,
                        title: specialDay.title,
                        body: "今天是\(specialDay.title)",
                        date: triggerDate
                    )
                    requestsByID[request.id] = request
                }
            }
        }

        return requestsByID.values.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.id < $1.id
        }
    }

    private func occurrenceStarts(
        for schedule: ScheduleItem,
        referenceDate: Date,
        horizonEnd: Date
    ) -> [Date] {
        let startDay = schedule.startDay
        let endDay = min(schedule.coverageEndDay, DayID(horizonEnd))
        guard startDay <= endDay else {
            return []
        }

        switch schedule.recurrence {
        case .none:
            guard isInRange(schedule.startDate, referenceDate: schedule.startDate, horizonEnd: horizonEnd) else {
                return []
            }
            return [schedule.startDate]
        case .daily:
            guard let repeatUntilDay = schedule.repeatUntilDay else {
                return []
            }
            let firstDay = max(startDay, DayID(referenceDate))
            let lastDay = min(repeatUntilDay, endDay)
            guard firstDay <= lastDay else {
                return []
            }
            return dates(for: firstDay, through: lastDay, matching: { _ in true }, schedule: schedule)
        case .weekly:
            guard let repeatUntilDay = schedule.repeatUntilDay else {
                return []
            }
            let firstDay = max(startDay, DayID(referenceDate))
            let lastDay = min(repeatUntilDay, endDay)
            guard firstDay <= lastDay else {
                return []
            }
            return dates(
                for: firstDay,
                through: lastDay,
                matching: { day in startDay.days(to: day).isMultiple(of: 7) },
                schedule: schedule
            )
        }
    }

    private func dates(
        for firstDay: DayID,
        through lastDay: DayID,
        matching predicate: (DayID) -> Bool,
        schedule: ScheduleItem
    ) -> [Date] {
        var dates: [Date] = []
        var day = firstDay
        while day <= lastDay {
            if predicate(day), let date = scheduleDate(for: day, schedule: schedule) {
                dates.append(date)
            }
            day = day.adding(days: 1)
        }
        return dates
    }

    private func scheduleDate(for day: DayID, schedule: ScheduleItem) -> Date? {
        guard let dayDate = day.date(in: calendar.timeZone) else {
            return nil
        }

        if schedule.isAllDay {
            return dayDate
        }

        let components = calendar.dateComponents([.hour, .minute, .second], from: schedule.startDate)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: dayDate
        )
    }

    private func dayTriggerDate(
        for day: DayID,
        preferences: CalendarNotificationPreferences
    ) -> Date? {
        guard let dayDate = day.date(in: calendar.timeZone) else {
            return nil
        }

        return calendar.date(
            bySettingHour: preferences.dayTriggerHour,
            minute: preferences.dayTriggerMinute,
            second: 0,
            of: dayDate
        )
    }

    private func makeRequest(
        id: String,
        kind: CalendarNotificationKind,
        title: String,
        body: String,
        date: Date
    ) throws -> CalendarNotificationRequest {
        do {
            return try CalendarNotificationRequest(
                id: id,
                kind: kind,
                title: title,
                body: body,
                date: date
            )
        } catch let error as CalendarNotificationRequestValidationError {
            throw CalendarNotificationPlanError.invalidRequest(error)
        }
    }

    private func isInRange(_ date: Date, referenceDate: Date, horizonEnd: Date) -> Bool {
        referenceDate <= date && date <= horizonEnd
    }

    private func timeDescription(for date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        return calendar
    }
}
