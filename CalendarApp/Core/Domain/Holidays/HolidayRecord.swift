import Foundation

/// The exceptional work status supplied by a holiday data source.
enum HolidayRecordKind: String, Codable, Hashable, Sendable {
    case holiday
    case makeupWorkday

    var workStatus: WorkStatus {
        switch self {
        case .holiday:
            .holiday
        case .makeupWorkday:
            .makeupWorkday
        }
    }
}

/// A normalized holiday or makeup-workday record for one calendar day.
struct HolidayRecord: Codable, Hashable, Identifiable, Sendable {
    let dayID: DayID
    let name: String
    let kind: HolidayRecordKind

    var id: DayID { dayID }

    var workStatus: WorkStatus { kind.workStatus }

    init(dayID: DayID, name: String, kind: HolidayRecordKind) {
        self.dayID = dayID
        self.name = name
        self.kind = kind
    }
}

/// A validated, source-aware set of exceptional dates for one Gregorian year.
struct HolidayYearSnapshot: Codable, Hashable, Sendable {
    let year: Int
    let providerID: String
    let fetchedAt: Date
    let sourceURL: URL?
    let records: [HolidayRecord]

    init(
        year: Int,
        providerID: String,
        fetchedAt: Date,
        sourceURL: URL? = nil,
        records: [HolidayRecord]
    ) throws {
        guard (1...9999).contains(year) else {
            throw HolidayDataError.invalidYear(year)
        }

        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HolidayDataError.emptyProviderID
        }

        guard !records.isEmpty else {
            throw HolidayDataError.emptyRecords(year)
        }

        var knownDays = Set<DayID>()
        for record in records {
            guard record.dayID.year == year else {
                throw HolidayDataError.recordYearMismatch(
                    dayID: record.dayID,
                    expectedYear: year
                )
            }

            guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HolidayDataError.emptyName(record.dayID)
            }

            guard knownDays.insert(record.dayID).inserted else {
                throw HolidayDataError.duplicateDate(record.dayID)
            }
        }

        self.year = year
        self.providerID = providerID
        self.fetchedAt = fetchedAt
        self.sourceURL = sourceURL
        self.records = records.sorted { $0.dayID < $1.dayID }
    }
}

enum HolidayDataError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case emptyProviderID
    case emptyRecords(Int)
    case recordYearMismatch(dayID: DayID, expectedYear: Int)
    case emptyName(DayID)
    case duplicateDate(DayID)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            "无效的公历年份：\(year)"
        case .emptyProviderID:
            "节假日数据源标识不能为空"
        case let .emptyRecords(year):
            "\(year) 年节假日记录为空"
        case let .recordYearMismatch(dayID, expectedYear):
            "日期 \(dayID) 不属于请求的 \(expectedYear) 年"
        case let .emptyName(dayID):
            "日期 \(dayID) 缺少节假日名称"
        case let .duplicateDate(dayID):
            "日期 \(dayID) 存在重复或冲突记录"
        case let .invalidDate(value):
            "无法解析节假日日期：\(value)"
        }
    }
}
