import Foundation
import SwiftData

@Model
final class CachedHolidayRecordModel {
    var id: UUID
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    var year: Int
    var month: Int
    var day: Int
    var name: String
    var kindRawValue: String
    var snapshot: HolidaySnapshotModel?

    init(record: HolidayRecord, id: UUID = UUID()) {
        self.id = id
        self.calendarIdentifier = record.dayID.calendarIdentifier
        self.timeZoneIdentifier = record.dayID.timeZoneIdentifier
        self.year = record.dayID.year
        self.month = record.dayID.month
        self.day = record.dayID.day
        self.name = record.name
        self.kindRawValue = record.kind.rawValue
    }

    func makeDomainRecord() throws -> HolidayRecord {
        guard let dayID = DayID(
            year: year,
            month: month,
            day: day,
            calendarIdentifier: calendarIdentifier,
            timeZoneIdentifier: timeZoneIdentifier
        ),
        let kind = HolidayRecordKind(rawValue: kindRawValue) else {
            throw HolidayCacheError.invalidRecord
        }

        return HolidayRecord(dayID: dayID, name: name, kind: kind)
    }
}
