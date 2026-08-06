import Foundation
import SwiftData

@Model
final class SpecialDayModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    var year: Int
    var month: Int
    var day: Int
    var recurrenceRawValue: String
    var colorRawValue: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        specialDay: SpecialDay,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        id = specialDay.id
        title = specialDay.title
        calendarIdentifier = specialDay.anchorDay.calendarIdentifier
        timeZoneIdentifier = specialDay.anchorDay.timeZoneIdentifier
        year = specialDay.anchorDay.year
        month = specialDay.anchorDay.month
        day = specialDay.anchorDay.day
        recurrenceRawValue = specialDay.recurrence.rawValue
        colorRawValue = specialDay.color.rawValue
        note = specialDay.note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(from specialDay: SpecialDay, updatedAt: Date = .now) {
        title = specialDay.title
        calendarIdentifier = specialDay.anchorDay.calendarIdentifier
        timeZoneIdentifier = specialDay.anchorDay.timeZoneIdentifier
        year = specialDay.anchorDay.year
        month = specialDay.anchorDay.month
        day = specialDay.anchorDay.day
        recurrenceRawValue = specialDay.recurrence.rawValue
        colorRawValue = specialDay.color.rawValue
        note = specialDay.note
        self.updatedAt = updatedAt
    }

    func makeDomain() throws -> SpecialDay {
        guard let recurrence = SpecialDayRecurrence(rawValue: recurrenceRawValue),
              let color = PersonalDateColor(rawValue: colorRawValue),
              let anchorDay = DayID(
                  year: year,
                  month: month,
                  day: day,
                  calendarIdentifier: calendarIdentifier,
                  timeZoneIdentifier: timeZoneIdentifier
              ) else {
            throw VacationRepositoryError.invalidModel
        }

        do {
            return try SpecialDay(
                id: id,
                title: title,
                anchorDay: anchorDay,
                recurrence: recurrence,
                color: color,
                note: note
            )
        } catch {
            throw VacationRepositoryError.invalidModel
        }
    }
}
