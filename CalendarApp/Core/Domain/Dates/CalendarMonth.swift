import Foundation

struct CalendarMonth: Codable, Comparable, Hashable, Identifiable, Sendable {
    let year: Int
    let month: Int

    init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else {
            return nil
        }

        self.year = year
        self.month = month
    }

    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    var title: String {
        "\(year)年\(month)月"
    }

    var firstDay: DayID {
        // The initializer validates the same range, so this cannot fail.
        DayID(year: year, month: month, day: 1)!
    }

    var daysInMonth: Int {
        let calendar = Self.gregorianCalendar
        return calendar.range(of: .day, in: .month, for: firstDay.date ?? .distantPast)?.count ?? 0
    }

    func adding(months: Int) -> CalendarMonth? {
        guard let date = firstDay.date,
              let result = Self.gregorianCalendar.date(byAdding: .month, value: months, to: date) else {
            return nil
        }

        let components = Self.gregorianCalendar.dateComponents([.year, .month], from: result)
        guard let year = components.year, let month = components.month else {
            return nil
        }

        return CalendarMonth(year: year, month: month)
    }

    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        return lhs.month < rhs.month
    }

    private static var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}

struct CalendarMonthDay: Hashable, Identifiable, Sendable {
    let dayID: DayID
    let isInDisplayedMonth: Bool

    var id: DayID { dayID }
}

/// A fixed seven-column month grid with Monday as the first weekday.
struct CalendarMonthGrid: Equatable, Sendable {
    static let defaultFirstWeekday = 2 // Calendar weekday: Sunday = 1, Monday = 2.

    let month: CalendarMonth
    let firstWeekday: Int
    let days: [CalendarMonthDay]

    init(
        month: CalendarMonth,
        firstWeekday: Int = CalendarMonthGrid.defaultFirstWeekday
    ) {
        let normalizedFirstWeekday = (1...7).contains(firstWeekday)
            ? firstWeekday
            : Self.defaultFirstWeekday
        let firstDay = month.firstDay
        let leadingDays = (firstDay.weekday() - normalizedFirstWeekday + 7) % 7
        let requiredCells = leadingDays + month.daysInMonth
        let cellCount = ((requiredCells + 6) / 7) * 7
        let gridStart = firstDay.adding(days: -leadingDays)

        self.month = month
        self.firstWeekday = normalizedFirstWeekday
        self.days = (0..<cellCount).map { offset in
            let dayID = gridStart.adding(days: offset)
            return CalendarMonthDay(
                dayID: dayID,
                isInDisplayedMonth: dayID.year == month.year && dayID.month == month.month
            )
        }
    }

    var rowCount: Int { days.count / 7 }
}
