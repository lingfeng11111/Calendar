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

private enum SolarTermCatalog {
    static let names = [
        "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
        "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
        "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"
    ]
}

/// A replaceable remote provider for the 24 solar terms.
///
/// The endpoint supplies the dates; the app only keeps the stable term names
/// in this provider and never embeds an annual date table.
struct SolarTermsDateKnowledgeProvider: DateKnowledgeProvider, Sendable {
    static let defaultBaseURL = URL(string: "https://collect.xmwxxc.com/collect/solar_terms")!

    let id: String
    let baseURL: URL
    let client: HTTPClient

    private let now: @Sendable () -> Date

    init(
        baseURL: URL = Self.defaultBaseURL,
        client: HTTPClient = HTTPClient(timeoutInterval: 3),
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
                for name in SolarTermCatalog.names {
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

/// A deterministic approximation used when the remote solar-term service is
/// unavailable. The formula is versioned as a rule, not as an annual date
/// table, so future years remain computable without shipping hardcoded dates.
struct SolarTermsAlgorithmProvider: DateKnowledgeProvider, Sendable {
    let id = "solar-terms-local-algorithm-v1"
    private static let algorithmVersion = "v1"

    private let now: @Sendable () -> Date

    private static let rules: [(name: String, month: Int, coefficient: Double)] = [
        // The coefficients are calibrated for the Gregorian year formula;
        // month/day stays a rule-derived result and is never an annual table.
        ("立春", 2, 4.475), ("雨水", 2, 19.255), ("惊蛰", 3, 5.63),
        ("春分", 3, 20.646), ("清明", 4, 4.81), ("谷雨", 4, 20.1),
        ("立夏", 5, 5.52), ("小满", 5, 21.04), ("芒种", 6, 5.678),
        ("夏至", 6, 21.37), ("小暑", 7, 7.108), ("大暑", 7, 22.83),
        ("立秋", 8, 7.5), ("处暑", 8, 23.13), ("白露", 9, 7.646),
        ("秋分", 9, 23.042), ("寒露", 10, 8.318), ("霜降", 10, 23.438),
        ("立冬", 11, 7.438), ("小雪", 11, 22.36), ("大雪", 12, 7.18),
        ("冬至", 12, 21.94), ("小寒", 1, 5.4055), ("大寒", 1, 20.12)
    ]

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }

        let yearInCentury = year % 100
        let annotations = Self.rules.compactMap { rule -> DayAnnotation? in
            let correction = Int(floor(Double(yearInCentury) / 4.0))
            let day = Int(floor(Double(yearInCentury) * 0.2422 + rule.coefficient)) - correction
            guard let dayID = DayID(year: year, month: rule.month, day: day) else {
                return nil
            }
            return DayAnnotation(
                dayID: dayID,
                title: rule.name,
                kind: .solarTerm,
                sourceID: "\(id)-\(Self.algorithmVersion)"
            )
        }

        return try DateKnowledgeYearSnapshot(
            year: year,
            providerID: id,
            fetchedAt: now(),
            annotations: annotations
        )
    }
}

/// Keeps remote and local solar-term behavior together so a remote outage does
/// not make the traditional-festival source look like a complete success.
struct SolarTermsResilientProvider: DateKnowledgeProvider, Sendable {
    let id = "solar-terms-resilient-v1"
    private let primary: any DateKnowledgeProvider
    private let fallback: any DateKnowledgeProvider

    init(
        primary: any DateKnowledgeProvider = SolarTermsDateKnowledgeProvider(),
        fallback: any DateKnowledgeProvider = SolarTermsAlgorithmProvider()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        do {
            return try await primary.fetchYear(year)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.fetchYear(year)
        }
    }
}

/// Computes major traditional festivals from Foundation's Chinese calendar.
/// Gregorian dates are discovered by calendar conversion rather than stored as
/// a year-by-year table.
struct ChineseTraditionalFestivalProvider: DateKnowledgeProvider, Sendable {
    let id = "traditional-festivals-chinese-calendar-v1"

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }

        var chineseCalendar = Calendar(identifier: .chinese)
        chineseCalendar.timeZone = DayID.defaultTimeZone
        chineseCalendar.locale = Locale(identifier: "zh_CN")

        let startDay = DayID(year: year, month: 1, day: 1)!
        let dayCount = Calendar(identifier: .gregorian).range(
            of: .day,
            in: .year,
            for: startDay.date ?? .distantPast
        )?.count ?? 365
        let dayIDs = (0..<dayCount).map { startDay.adding(days: $0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        let annotations = dayIDs.compactMap { dayID -> DayAnnotation? in
            guard let date = dayID.date else {
                return nil
            }

            let components = chineseCalendar.dateComponents([.month, .day], from: date)
            guard let lunarMonth = components.month, let lunarDay = components.day else {
                return nil
            }

            let title: String?
            switch (lunarMonth, lunarDay) {
            case (1, 1): title = "春节"
            case (1, 15): title = "元宵节"
            case (5, 5): title = "端午节"
            case (7, 7): title = "七夕"
            case (7, 15): title = "中元节"
            case (8, 15): title = "中秋节"
            case (9, 9): title = "重阳节"
            case (12, 8): title = "腊八节"
            default: title = nil
            }

            if let title {
                return DayAnnotation(
                    dayID: dayID,
                    title: title,
                    kind: .importantTraditionalFestival,
                    sourceID: id
                )
            }

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            let nextComponents = chineseCalendar.dateComponents([.month, .day], from: nextDate)
            guard nextComponents.month == 1, nextComponents.day == 1 else {
                return nil
            }

            return DayAnnotation(
                dayID: dayID,
                title: "除夕",
                kind: .importantTraditionalFestival,
                sourceID: id
            )
        }

        return try DateKnowledgeYearSnapshot(
            year: year,
            providerID: id,
            fetchedAt: now(),
            annotations: annotations
        )
    }
}

/// Merges independently replaceable sources. One failing source does not
/// erase the successful sources, which keeps the calendar useful offline.
struct CompositeDateKnowledgeProvider: DateKnowledgeProvider, Sendable {
    let id: String
    let providers: [any DateKnowledgeProvider]

    init(
        id: String = "date-knowledge-composite-v3",
        providers: [any DateKnowledgeProvider]
    ) {
        self.id = id
        self.providers = providers
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        var snapshots: [DateKnowledgeYearSnapshot] = []
        for provider in providers {
            do {
                snapshots.append(try await provider.fetchYear(year))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        guard !snapshots.isEmpty else {
            throw DateKnowledgeError.notAvailable
        }

        var unique: [String: DayAnnotation] = [:]
        for annotation in snapshots.flatMap(\.annotations) {
            let key = "\(annotation.kind.rawValue)|\(annotation.title)"
            unique[key] = unique[key] ?? annotation
        }

        let usesSolarTermFallback = snapshots.contains {
            $0.annotations.contains { $0.sourceID.hasPrefix("solar-terms-local-algorithm") }
        }
        return try DateKnowledgeYearSnapshot(
            year: year,
            providerID: usesSolarTermFallback ? "\(id)-fallback" : id,
            fetchedAt: snapshots.map(\.fetchedAt).max() ?? Date(),
            annotations: Array(unique.values)
        )
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
    private let fallbackProvider: (any DateKnowledgeProvider)?
    private let cacheMaxAge: TimeInterval
    private let now: @Sendable () -> Date

    private(set) var lastLoadState: DateKnowledgeLoadState = .idle

    init(
        modelContext: ModelContext? = nil,
        primaryProvider: any DateKnowledgeProvider,
        fallbackProvider: (any DateKnowledgeProvider)? = nil,
        cacheMaxAge: TimeInterval = 30 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContext = modelContext
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.cacheMaxAge = max(cacheMaxAge, 60)
        self.now = now
    }

    func snapshot(for year: Int) async throws -> DateKnowledgeYearSnapshot {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }

        lastLoadState = .loading

        // Cache entries from a previous provider graph are deliberately
        // ignored. The repository cache is keyed by the current graph ID so
        // adding a new source or rule version can refresh existing installs.
        let cacheProviderIDs: [String]? = fallbackProvider == nil
            ? nil
            : [primaryProvider.id, "\(primaryProvider.id)-fallback"]
        if let cached = try cachedSnapshot(
            for: year,
            compatibleProviderIDs: cacheProviderIDs
        ),
           now().timeIntervalSince(cached.cachedAt) < cacheMaxAge {
            lastLoadState = cached.snapshot.providerID.hasSuffix("-fallback")
                ? .usingFallback
                : .usingCache
            return cached.snapshot
        }

        do {
            let snapshot = try await primaryProvider.fetchYear(year)
            try save(snapshot)
            lastLoadState = snapshot.providerID.hasSuffix("-fallback")
                ? .usingFallback
                : .available
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let fallbackProvider {
                do {
                    let snapshot = try await fallbackProvider.fetchYear(year)
                    try save(snapshot)
                    lastLoadState = .usingFallback
                    return snapshot
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A stale persisted snapshot is still preferable to no
                    // date knowledge at all, so continue to the cache below.
                }
            }

            if let cached = try cachedSnapshot(
                for: year,
                compatibleProviderIDs: cacheProviderIDs
            ) {
                lastLoadState = cached.snapshot.providerID.hasSuffix("-fallback")
                    ? .usingFallback
                    : .usingCache
                return cached.snapshot
            }
            lastLoadState = .unavailable
            throw DateKnowledgeError.notAvailable
        }
    }

    private func cachedSnapshot(
        for year: Int,
        compatibleProviderIDs: [String]? = nil
    ) throws -> CachedSnapshot? {
        guard let modelContext else {
            return nil
        }

        do {
            let models = try modelContext.fetch(FetchDescriptor<DateKnowledgeSnapshotModel>())
                .filter { model in
                    guard model.year == year, model.isValid else {
                        return false
                    }
                    guard let compatibleProviderIDs else {
                        return true
                    }
                    return compatibleProviderIDs.contains(model.providerID)
                }
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
