import Foundation

struct DayStatusResolver: Sendable {
    let defaultTimeZone: TimeZone

    init(defaultTimeZone: TimeZone = DayID.defaultTimeZone) {
        self.defaultTimeZone = defaultTimeZone
    }

    func defaultStatus(for dayID: DayID) -> WorkStatus {
        dayID.isWeekend(in: defaultTimeZone) ? .weekend : .workday
    }

    func resolve(
        dayID: DayID,
        userOverride: UserDayOverride? = nil
    ) -> DayPresentation {
        resolve(
            dayID: dayID,
            userOverride: userOverride,
            holidayRecord: nil
        )
    }

    func resolve(
        dayID: DayID,
        userOverride: UserDayOverride? = nil,
        holidayRecord: HolidayRecord?,
        holidayProviderID: String = "official"
    ) -> DayPresentation {
        if let userOverride {
            return DayPresentation(
                dayID: dayID,
                workStatus: userOverride.status,
                statusSource: .userOverride,
                statusReason: userOverride.reason
            )
        }

        if let holidayRecord {
            return DayPresentation(
                dayID: dayID,
                workStatus: holidayRecord.workStatus,
                statusSource: .holidayProvider(providerID: holidayProviderID),
                statusReason: holidayRecord.name,
                holidayLabels: [holidayRecord.name]
            )
        }

        return DayPresentation(
            dayID: dayID,
            workStatus: defaultStatus(for: dayID),
            statusSource: .defaultWeekRule
        )
    }
}
