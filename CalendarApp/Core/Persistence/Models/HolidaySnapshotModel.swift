import Foundation
import SwiftData

@Model
final class HolidaySnapshotModel {
    @Attribute(.unique) var year: Int
    var id: UUID
    var providerID: String
    var sourceURLString: String?
    var fetchedAt: Date
    var cachedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var dataVersion: String
    var isValid: Bool

    @Relationship(deleteRule: .cascade, inverse: \CachedHolidayRecordModel.snapshot)
    var records: [CachedHolidayRecordModel] = []

    init(
        year: Int,
        id: UUID = UUID(),
        providerID: String,
        sourceURLString: String?,
        fetchedAt: Date,
        cachedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        dataVersion: String = "1",
        isValid: Bool = true
    ) {
        self.year = year
        self.id = id
        self.providerID = providerID
        self.sourceURLString = sourceURLString
        self.fetchedAt = fetchedAt
        self.cachedAt = cachedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dataVersion = dataVersion
        self.isValid = isValid
    }

    convenience init(snapshot: HolidayYearSnapshot, cachedAt: Date) {
        self.init(
            year: snapshot.year,
            providerID: snapshot.providerID,
            sourceURLString: snapshot.sourceURL?.absoluteString,
            fetchedAt: snapshot.fetchedAt,
            cachedAt: cachedAt,
            createdAt: cachedAt,
            updatedAt: cachedAt
        )
        replaceRecords(with: snapshot)
    }

    func replace(with snapshot: HolidayYearSnapshot, cachedAt: Date) {
        providerID = snapshot.providerID
        sourceURLString = snapshot.sourceURL?.absoluteString
        fetchedAt = snapshot.fetchedAt
        self.cachedAt = cachedAt
        updatedAt = cachedAt
        dataVersion = "1"
        isValid = true
        replaceRecords(with: snapshot)
    }

    func makeDomainSnapshot() throws -> HolidayYearSnapshot {
        let sourceURL = sourceURLString.flatMap(URL.init(string:))
        let domainRecords = try records.map { try $0.makeDomainRecord() }

        return try HolidayYearSnapshot(
            year: year,
            providerID: providerID,
            fetchedAt: fetchedAt,
            sourceURL: sourceURL,
            records: domainRecords
        )
    }

    private func replaceRecords(with snapshot: HolidayYearSnapshot) {
        records = snapshot.records.map { CachedHolidayRecordModel(record: $0) }
        records.forEach { $0.snapshot = self }
    }
}
