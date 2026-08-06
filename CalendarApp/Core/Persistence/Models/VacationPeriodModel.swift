import Foundation
import SwiftData

@Model
final class VacationPeriodModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    var startCalendarIdentifier: String
    var startTimeZoneIdentifier: String
    var startYear: Int
    var startMonth: Int
    var startDay: Int
    var endCalendarIdentifier: String
    var endTimeZoneIdentifier: String
    var endYear: Int
    var endMonth: Int
    var endDay: Int
    var colorRawValue: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        period: VacationPeriod,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        id = period.id
        title = period.title
        kindRawValue = period.kind.rawValue
        startCalendarIdentifier = period.startDay.calendarIdentifier
        startTimeZoneIdentifier = period.startDay.timeZoneIdentifier
        startYear = period.startDay.year
        startMonth = period.startDay.month
        startDay = period.startDay.day
        endCalendarIdentifier = period.endDay.calendarIdentifier
        endTimeZoneIdentifier = period.endDay.timeZoneIdentifier
        endYear = period.endDay.year
        endMonth = period.endDay.month
        endDay = period.endDay.day
        colorRawValue = period.color.rawValue
        note = period.note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(from period: VacationPeriod, updatedAt: Date = .now) {
        title = period.title
        kindRawValue = period.kind.rawValue
        startCalendarIdentifier = period.startDay.calendarIdentifier
        startTimeZoneIdentifier = period.startDay.timeZoneIdentifier
        startYear = period.startDay.year
        startMonth = period.startDay.month
        startDay = period.startDay.day
        endCalendarIdentifier = period.endDay.calendarIdentifier
        endTimeZoneIdentifier = period.endDay.timeZoneIdentifier
        endYear = period.endDay.year
        endMonth = period.endDay.month
        endDay = period.endDay.day
        colorRawValue = period.color.rawValue
        note = period.note
        self.updatedAt = updatedAt
    }

    func makeDomain() throws -> VacationPeriod {
        guard let kind = VacationKind(rawValue: kindRawValue),
              let color = PersonalDateColor(rawValue: colorRawValue),
              let startDay = DayID(
                  year: startYear,
                  month: startMonth,
                  day: startDay,
                  calendarIdentifier: startCalendarIdentifier,
                  timeZoneIdentifier: startTimeZoneIdentifier
              ),
              let endDay = DayID(
                  year: endYear,
                  month: endMonth,
                  day: endDay,
                  calendarIdentifier: endCalendarIdentifier,
                  timeZoneIdentifier: endTimeZoneIdentifier
              ) else {
            throw VacationRepositoryError.invalidModel
        }

        do {
            return try VacationPeriod(
                id: id,
                title: title,
                kind: kind,
                startDay: startDay,
                endDay: endDay,
                color: color,
                note: note
            )
        } catch {
            throw VacationRepositoryError.invalidModel
        }
    }
}
