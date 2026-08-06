import Foundation

/// A calendar-day identity independent from a wall-clock time.
///
/// The default identity is a Gregorian day in Asia/Shanghai. Concrete event
/// times remain `Date` values and are converted into a `DayID` at the boundary.
struct DayID: Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    static let defaultCalendarIdentifier = "gregorian"
    static let defaultTimeZoneIdentifier = "Asia/Shanghai"

    let calendarIdentifier: String
    let timeZoneIdentifier: String
    let year: Int
    let month: Int
    let day: Int

    init?(
        year: Int,
        month: Int,
        day: Int,
        calendarIdentifier: String = DayID.defaultCalendarIdentifier,
        timeZoneIdentifier: String = DayID.defaultTimeZoneIdentifier
    ) {
        guard calendarIdentifier == Self.defaultCalendarIdentifier,
              TimeZone(identifier: timeZoneIdentifier) != nil
        else {
            return nil
        }

        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return nil
        }

        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year,
              normalized.month == month,
              normalized.day == day else {
            return nil
        }

        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, timeZone: TimeZone = Self.defaultTimeZone) {
        let calendar = Self.gregorianCalendar(timeZone: timeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        self.calendarIdentifier = Self.defaultCalendarIdentifier
        self.timeZoneIdentifier = timeZone.identifier
        self.year = components.year ?? 1
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    static var defaultTimeZone: TimeZone {
        TimeZone(identifier: defaultTimeZoneIdentifier) ?? .gmt
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var date: Date? {
        date(in: Self.defaultTimeZone)
    }

    func date(in timeZone: TimeZone) -> Date? {
        let calendar = Self.gregorianCalendar(timeZone: timeZone)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    func adding(days: Int) -> DayID {
        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let sourceDate = date(in: calendar.timeZone) ?? Date(timeIntervalSince1970: 0)
        let resultDate = calendar.date(byAdding: .day, value: days, to: sourceDate) ?? sourceDate
        return DayID(resultDate, timeZone: calendar.timeZone)
    }

    func days(to other: DayID) -> Int {
        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let start = date(in: calendar.timeZone) ?? Date(timeIntervalSince1970: 0)
        let end = other.date(in: calendar.timeZone) ?? start
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func weekday(in timeZone: TimeZone? = nil) -> Int {
        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZone?.identifier ?? timeZoneIdentifier)
        let sourceDate = date(in: calendar.timeZone) ?? Date(timeIntervalSince1970: 0)
        return calendar.component(.weekday, from: sourceDate)
    }

    func isWeekend(in timeZone: TimeZone? = nil) -> Bool {
        let weekday = weekday(in: timeZone)
        return weekday == 1 || weekday == 7
    }

    static func < (lhs: DayID, rhs: DayID) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        if lhs.month != rhs.month {
            return lhs.month < rhs.month
        }
        return lhs.day < rhs.day
    }

    private static func gregorianCalendar(timeZoneIdentifier: String) -> Calendar {
        gregorianCalendar(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? defaultTimeZone)
    }

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}
