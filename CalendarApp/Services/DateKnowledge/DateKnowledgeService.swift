import Foundation
import SwiftData

/// The response shape used by the no-key solar-term endpoint.
private struct SolarTermsResponseDTO: Decodable, Sendable {
    let code: Int
    let data: [SolarTermDTO]
}

private struct SolarTermDTO: Decodable, Sendable {
    let jqName: String
    let jqTime: String

    enum CodingKeys: String, CodingKey {
        case jqName = "jq_name"
        case jqTime = "jq_time"
    }
}

/// A replaceable remote provider for the 24 solar terms.
///
/// The endpoint supplies the dates; the app only keeps the stable term names
/// in this provider and never embeds an annual date table.
struct SolarTermsDateKnowledgeProvider: DateKnowledgeProvider, Sendable {
    static let defaultBaseURL = URL(string: "https://collect.xmwxxc.com/collect/solar_terms")!

    private static let termNames = [
        "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
        "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
        "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"
    ]

    let id: String
    let baseURL: URL
    let client: HTTPClient

    private let now: @Sendable () -> Date

    init(
        baseURL: URL = Self.defaultBaseURL,
        client: HTTPClient = HTTPClient(),
        id: String = "solar-terms-xmwxxc",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.client = client
        self.id = id
        self.now = now
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }

        do {
            let annotations = try await withThrowingTaskGroup(of: [DayAnnotation].self) { group in
                for name in Self.termNames {
                    group.addTask {
                        let response = try await client.get(
                            SolarTermsResponseDTO.self,
                            from: try endpoint(for: name, year: year)
                        )

                        guard response.code == 1 else {
                            throw DateKnowledgeError.invalidResponse
                        }

                        return try response.data.map { term in
                            guard let dayID = Self.makeDayID(from: term.jqTime),
                                  dayID.year == year else {
                                throw DateKnowledgeError.invalidDate(term.jqTime)
                            }

                            return DayAnnotation(
                                dayID: dayID,
                                title: term.jqName,
                                kind: .solarTerm,
                                sourceID: id,
                                sourceURL: baseURL
                            )
                        }
                    }
                }

                var values: [[DayAnnotation]] = []
                for try await value in group {
                    values.append(value)
                }
                return values.flatMap { $0 }
            }

            return try DateKnowledgeYearSnapshot(
                year: year,
                providerID: id,
                fetchedAt: now(),
                sourceURL: baseURL,
                annotations: annotations
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DateKnowledgeError {
            throw error
        } catch let error as HTTPClientError {
            if case .cancelled = error {
                throw CancellationError()
            }
            throw DateKnowledgeError.notAvailable
        } catch {
            throw DateKnowledgeError.notAvailable
        }
    }

    func endpoint(for name: String, year: Int) throws -> URL {
        guard baseURL.scheme != nil, baseURL.host != nil else {
            throw DateKnowledgeError.invalidResponse
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "year", value: String(year))
        ]

        guard let url = components?.url else {
            throw DateKnowledgeError.invalidResponse
        }
        return url
    }

    private static func makeDayID(from value: String) -> DayID? {
        let parts = value.split { character in
            "年月日时分秒".contains(character)
        }
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return DayID(year: year, month: month, day: day)
    }
}

@MainActor
final class DateKnowledgeRepository: DateKnowledgeRepositoryProtocol {
    private struct CachedSnapshot {
        let snapshot: DateKnowledgeYearSnapshot
        let cachedAt: Date
    }

    private let modelContext: ModelContext?
    private let primaryProvider: any DateKnowledgeProvider
    private let cacheMaxAge: TimeInterval
    private let now: @Sendable () -> Date

    init(
        modelContext: ModelContext? = nil,
        primaryProvider: any DateKnowledgeProvider,
        cacheMaxAge: TimeInterval = 30 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContext = modelContext
        self.primaryProvider = primaryProvider
        self.cacheMaxAge = max(cacheMaxAge, 60)
        self.now = now
    }

    func snapshot(for year: Int) async throws -> DateKnowledgeYearSnapshot {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }

        if let cached = try cachedSnapshot(for: year),
           now().timeIntervalSince(cached.cachedAt) < cacheMaxAge {
            return cached.snapshot
        }

        do {
            let snapshot = try await primaryProvider.fetchYear(year)
            try save(snapshot)
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cached = try cachedSnapshot(for: year) {
                return cached.snapshot
            }
            throw DateKnowledgeError.notAvailable
        }
    }

    private func cachedSnapshot(for year: Int) throws -> CachedSnapshot? {
        guard let modelContext else {
            return nil
        }

        do {
            let models = try modelContext.fetch(FetchDescriptor<DateKnowledgeSnapshotModel>())
                .filter { $0.year == year && $0.isValid }
                .sorted { $0.cachedAt > $1.cachedAt }

            for model in models {
                do {
                    return CachedSnapshot(
                        snapshot: try model.makeDomainSnapshot(),
                        cachedAt: model.cachedAt
                    )
                } catch {
                    model.isValid = false
                }
            }
            return nil
        } catch {
            throw DateKnowledgeError.notAvailable
        }
    }

    private func save(_ snapshot: DateKnowledgeYearSnapshot) throws {
        guard let modelContext else {
            return
        }

        let timestamp = now()
        do {
            if let existing = try modelContext.fetch(FetchDescriptor<DateKnowledgeSnapshotModel>())
                .first(where: { $0.year == snapshot.year }) {
                existing.replace(with: snapshot, cachedAt: timestamp)
            } else {
                modelContext.insert(DateKnowledgeSnapshotModel(snapshot: snapshot, cachedAt: timestamp))
            }
            try modelContext.save()
        } catch {
            throw DateKnowledgeError.notAvailable
        }
    }
}
