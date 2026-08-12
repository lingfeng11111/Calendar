import Foundation

struct CalendarWidgetSnapshotComposer {
    private var calendar: Calendar

    init(calendar: Calendar = Self.defaultCalendar) {
        var calendar = calendar
        calendar.timeZone = DayID.defaultTimeZone
        self.calendar = calendar
    }

    func makeSnapshot(
        referenceDate: Date,
        presentation: DayPresentation,
        upcomingDates: [UpcomingDateSummary]
    ) -> CalendarWidgetSnapshot {
        let nextDate = upcomingDates
            .filter { $0.dayID > presentation.dayID }
            .sorted { $0.dayID < $1.dayID }
            .first
            .map { summary in
                CalendarWidgetNextDate(
                    dayID: summary.dayID.description,
                    dateLabel: dateLabel(for: summary.dayID),
                    title: summary.title,
                    subtitle: summary.subtitle
                )
            }

        return CalendarWidgetSnapshot(
            generatedAt: referenceDate,
            dayID: presentation.dayID.description,
            dateLabel: dateLabel(for: presentation.dayID),
            statusKey: statusKey(for: presentation.workStatus),
            statusLabel: statusLabel(for: presentation.workStatus),
            statusReason: presentation.statusReason,
            primaryTitle: presentation.primaryAnnotation?.title
                ?? presentation.specialDayLabels.first
                ?? presentation.vacationLabels.first,
            primaryKind: presentation.primaryAnnotation?.kind.rawValue,
            scheduleCount: presentation.scheduleCount,
            vacationLabels: presentation.vacationLabels,
            specialDayLabels: presentation.specialDayLabels,
            nextDate: nextDate
        )
    }

    private func dateLabel(for dayID: DayID) -> String {
        let weekday = calendar.component(.weekday, from: dayID.date ?? Date())
        let weekdayLabel = ["日", "一", "二", "三", "四", "五", "六"][max(1, min(7, weekday)) - 1]
        return String(dayID.month) + "月" + String(dayID.day) + "日 周" + weekdayLabel
    }

    private func statusKey(for status: WorkStatus) -> String {
        switch status {
        case .workday:
            "workday"
        case .weekend:
            "weekend"
        case .holiday:
            "holiday"
        case .makeupWorkday:
            "makeupWorkday"
        case .unknown:
            "unknown"
        }
    }

    private func statusLabel(for status: WorkStatus) -> String {
        switch status {
        case .workday:
            "工作日"
        case .weekend:
            "周末"
        case .holiday:
            "休息日"
        case .makeupWorkday:
            "调休补班"
        case .unknown:
            "状态待确认"
        }
    }

    private static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        return calendar
    }
}
