import Foundation
import SwiftData

@Model
final class DateKnowledgeSnapshotModel {
    @Attribute(.unique) var year: Int
    var id: UUID
    var providerID: String
    var sourceURLString: String?
    var fetchedAt: Date
    var cachedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var dataVersion: String
    var annotationsData: Data
    var isValid: Bool

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
        annotationsData: Data,
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
        self.annotationsData = annotationsData
        self.isValid = isValid
    }

    convenience init(snapshot: DateKnowledgeYearSnapshot, cachedAt: Date) {
        self.init(
            year: snapshot.year,
            providerID: snapshot.providerID,
            sourceURLString: snapshot.sourceURL?.absoluteString,
            fetchedAt: snapshot.fetchedAt,
            cachedAt: cachedAt,
            createdAt: cachedAt,
            updatedAt: cachedAt,
            annotationsData: (try? JSONEncoder().encode(snapshot.annotations)) ?? Data()
        )
    }

    func replace(with snapshot: DateKnowledgeYearSnapshot, cachedAt: Date) {
        providerID = snapshot.providerID
        sourceURLString = snapshot.sourceURL?.absoluteString
        fetchedAt = snapshot.fetchedAt
        self.cachedAt = cachedAt
        updatedAt = cachedAt
        dataVersion = "1"
        annotationsData = (try? JSONEncoder().encode(snapshot.annotations)) ?? Data()
        isValid = true
    }

    func makeDomainSnapshot() throws -> DateKnowledgeYearSnapshot {
        let annotations = try JSONDecoder().decode([DayAnnotation].self, from: annotationsData)
        return try DateKnowledgeYearSnapshot(
            year: year,
            providerID: providerID,
            fetchedAt: fetchedAt,
            sourceURL: sourceURLString.flatMap(URL.init(string:)),
            annotations: annotations
        )
    }
}
