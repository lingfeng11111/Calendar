import Foundation

/// The three-year window used when checking holiday data around the current year.
struct HolidayRefreshWindow: Equatable, Sendable {
    let referenceYear: Int
    let years: [Int]

    init(referenceYear: Int) {
        self.referenceYear = referenceYear
        self.years = [referenceYear - 1, referenceYear, referenceYear + 1]
            .filter { (1...9999).contains($0) }
    }
}

enum HolidayYearRefreshState: Equatable, Sendable {
    case available(HolidayYearSnapshot)
    case notPublished
    case unavailable
}

struct HolidayRefreshReport: Equatable, Sendable {
    let window: HolidayRefreshWindow
    let states: [Int: HolidayYearRefreshState]

    func state(for year: Int) -> HolidayYearRefreshState? {
        states[year]
    }
}

/// Pure refresh timing rules kept outside the repository and the UI.
struct HolidayRefreshPolicy: Sendable {
    static let standard = HolidayRefreshPolicy()

    let regularCacheAge: TimeInterval
    let nextYearCacheAge: TimeInterval
    let nextYearProbeStartMonth: Int
    let nextYearProbeStartDay: Int
    let timeZoneIdentifier: String

    init(
        regularCacheAge: TimeInterval = 7 * 24 * 60 * 60,
        nextYearCacheAge: TimeInterval = 24 * 60 * 60,
        nextYearProbeStartMonth: Int = 10,
        nextYearProbeStartDay: Int = 1,
        timeZoneIdentifier: String = DayID.defaultTimeZoneIdentifier
    ) {
        self.regularCacheAge = max(regularCacheAge, 0)
        self.nextYearCacheAge = max(nextYearCacheAge, 0)
        self.nextYearProbeStartMonth = min(max(nextYearProbeStartMonth, 1), 12)
        self.nextYearProbeStartDay = min(max(nextYearProbeStartDay, 1), 31)
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func window(for referenceDate: Date) -> HolidayRefreshWindow {
        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let year = calendar.component(.year, from: referenceDate)
        return HolidayRefreshWindow(referenceYear: year)
    }

    func cacheMaxAge(for year: Int, referenceDate: Date) -> TimeInterval {
        let calendar = Self.gregorianCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let currentYear = calendar.component(.year, from: referenceDate)

        guard year == currentYear + 1,
              isWithinNextYearProbeWindow(referenceDate, calendar: calendar) else {
            return regularCacheAge
        }

        return nextYearCacheAge
    }

    func shouldRefresh(
        year: Int,
        cachedAt: Date?,
        referenceDate: Date
    ) -> Bool {
        guard let cachedAt else {
            return true
        }

        let age = referenceDate.timeIntervalSince(cachedAt)
        return age > cacheMaxAge(for: year, referenceDate: referenceDate)
    }

    private func isWithinNextYearProbeWindow(
        _ date: Date,
        calendar: Calendar
    ) -> Bool {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        return month > nextYearProbeStartMonth
            || (month == nextYearProbeStartMonth && day >= nextYearProbeStartDay)
    }

    private static func gregorianCalendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? DayID.defaultTimeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}
