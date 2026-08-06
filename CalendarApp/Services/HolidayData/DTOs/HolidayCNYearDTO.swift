import Foundation

/// DTO for the holiday-cn yearly JSON format.
struct HolidayCNYearDTO: Codable, Sendable {
    let year: Int
    let papers: [String]
    let days: [HolidayCNDayDTO]

    func makeSnapshot(
        providerID: String = "holiday-cn",
        fetchedAt: Date = .now,
        sourceURL: URL? = nil
    ) throws -> HolidayYearSnapshot {
        guard (1...9999).contains(year) else {
            throw HolidayDataError.invalidYear(year)
        }

        let records = try days.map { day in
            guard let dayID = Self.makeDayID(from: day.date) else {
                throw HolidayDataError.invalidDate(day.date)
            }

            let kind: HolidayRecordKind = day.isOffDay ? .holiday : .makeupWorkday
            return HolidayRecord(dayID: dayID, name: day.name, kind: kind)
        }

        do {
            return try HolidayYearSnapshot(
                year: year,
                providerID: providerID,
                fetchedAt: fetchedAt,
                sourceURL: sourceURL,
                records: records
            )
        } catch let error as HolidayDataError {
            throw error
        } catch {
            throw HolidayDataError.invalidDate("year=\(year)")
        }
    }

    private static func makeDayID(from value: String) -> DayID? {
        let characters = Array(value)
        guard characters.count >= 10,
              characters[4] == "-",
              characters[7] == "-" else {
            return nil
        }

        let datePart = String(characters[0..<10])
        let suffix = characters.count == 10 ? nil : String(characters[10...])
        guard suffix == nil || suffix?.first == "T" else {
            return nil
        }

        if let suffix, ISO8601DateFormatter().date(from: "\(datePart)\(suffix)") == nil {
            return nil
        }

        let parts = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return DayID(year: year, month: month, day: day)
    }
}

struct HolidayCNDayDTO: Codable, Sendable {
    let name: String
    let date: String
    let isOffDay: Bool
}
