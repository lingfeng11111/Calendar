import Foundation
import SwiftData

@Model
final class LocalScheduleItemModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrenceRawValue: String
    var repeatUntil: Date?
    var colorRawValue: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        schedule: ScheduleItem,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        id = schedule.id
        title = schedule.title
        startDate = schedule.startDate
        endDate = schedule.endDate
        isAllDay = schedule.isAllDay
        recurrenceRawValue = schedule.recurrence.rawValue
        repeatUntil = schedule.repeatUntil
        colorRawValue = schedule.color.rawValue
        note = schedule.note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(from schedule: ScheduleItem, updatedAt: Date = .now) {
        title = schedule.title
        startDate = schedule.startDate
        endDate = schedule.endDate
        isAllDay = schedule.isAllDay
        recurrenceRawValue = schedule.recurrence.rawValue
        repeatUntil = schedule.repeatUntil
        colorRawValue = schedule.color.rawValue
        note = schedule.note
        self.updatedAt = updatedAt
    }

    func makeDomain() throws -> ScheduleItem {
        guard let recurrence = ScheduleRecurrence(rawValue: recurrenceRawValue),
              let color = ScheduleColor(rawValue: colorRawValue) else {
            throw ScheduleRepositoryError.invalidModel
        }

        do {
            return try ScheduleItem(
                id: id,
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrence: recurrence,
                repeatUntil: repeatUntil,
                color: color,
                note: note
            )
        } catch {
            throw ScheduleRepositoryError.invalidModel
        }
    }
}
