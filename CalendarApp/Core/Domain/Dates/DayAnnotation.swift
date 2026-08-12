import Foundation

/// The single date-knowledge label that can be shown below a calendar number.
enum DayAnnotationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case makeupWorkday
    case publicHoliday
    case solarTerm
    case importantTraditionalFestival
    case observance

    /// Lower values win. This order is intentionally separate from WorkStatus.
    var displayPriority: Int {
        switch self {
        case .makeupWorkday:
            0
        case .publicHoliday:
            1
        case .solarTerm:
            2
        case .importantTraditionalFestival:
            3
        case .observance:
            4
        }
    }

    var displayName: String {
        switch self {
        case .makeupWorkday:
            "调休补班"
        case .publicHoliday:
            "法定节假日"
        case .solarTerm:
            "节气"
        case .importantTraditionalFestival:
            "传统节日"
        case .observance:
            "日期知识"
        }
    }
}

/// A source-aware date label used by both the month grid and the date detail.
struct DayAnnotation: Codable, Hashable, Identifiable, Sendable {
    let dayID: DayID
    let title: String
    let kind: DayAnnotationKind
    let sourceID: String
    let sourceURL: URL?

    var id: String {
        [
            dayID.description,
            kind.rawValue,
            title.lowercased(),
            sourceID
        ].joined(separator: "|")
    }

    init(
        dayID: DayID,
        title: String,
        kind: DayAnnotationKind,
        sourceID: String,
        sourceURL: URL? = nil
    ) {
        self.dayID = dayID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.sourceID = sourceID
        self.sourceURL = sourceURL
    }
}

/// A validated annual snapshot of solar terms and other date knowledge.
struct DateKnowledgeYearSnapshot: Codable, Hashable, Sendable {
    let year: Int
    let providerID: String
    let fetchedAt: Date
    let sourceURL: URL?
    let annotations: [DayAnnotation]

    init(
        year: Int,
        providerID: String,
        fetchedAt: Date,
        sourceURL: URL? = nil,
        annotations: [DayAnnotation]
    ) throws {
        guard (1...9999).contains(year) else {
            throw DateKnowledgeError.invalidYear(year)
        }
        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DateKnowledgeError.emptyProviderID
        }

        var seenIDs = Set<String>()
        for annotation in annotations {
            guard annotation.dayID.year == year else {
                throw DateKnowledgeError.annotationYearMismatch(
                    dayID: annotation.dayID,
                    expectedYear: year
                )
            }
            guard !annotation.title.isEmpty else {
                throw DateKnowledgeError.emptyTitle(annotation.dayID)
            }
            guard seenIDs.insert(annotation.id).inserted else {
                throw DateKnowledgeError.duplicateAnnotation(annotation.dayID)
            }
        }

        self.year = year
        self.providerID = providerID
        self.fetchedAt = fetchedAt
        self.sourceURL = sourceURL
        self.annotations = annotations.sorted {
            if $0.dayID != $1.dayID {
                return $0.dayID < $1.dayID
            }
            if $0.kind.displayPriority != $1.kind.displayPriority {
                return $0.kind.displayPriority < $1.kind.displayPriority
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func annotations(on dayID: DayID) -> [DayAnnotation] {
        annotations.filter { $0.dayID == dayID }
    }
}

enum DateKnowledgeError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case emptyProviderID
    case annotationYearMismatch(dayID: DayID, expectedYear: Int)
    case emptyTitle(DayID)
    case duplicateAnnotation(DayID)
    case invalidDate(String)
    case invalidResponse
    case notAvailable

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            "无效的日期知识年份：\(year)"
        case .emptyProviderID:
            "日期知识数据源标识不能为空"
        case let .annotationYearMismatch(dayID, expectedYear):
            "日期 \(dayID) 不属于请求的 \(expectedYear) 年"
        case let .emptyTitle(dayID):
            "日期 \(dayID) 缺少日期知识名称"
        case let .duplicateAnnotation(dayID):
            "日期 \(dayID) 存在重复日期知识记录"
        case let .invalidDate(value):
            "无法解析日期知识日期：\(value)"
        case .invalidResponse:
            "日期知识服务返回了无效数据"
        case .notAvailable:
            "日期知识暂不可用"
        }
    }
}

protocol DateKnowledgeProvider: Sendable {
    var id: String { get }
    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot
}

enum DateKnowledgeLoadState: Equatable, Sendable {
    case idle
    case loading
    case available
    case usingFallback
    case usingCache
    case unavailable

    var displayText: String? {
        switch self {
        case .idle, .available:
            nil
        case .loading:
            "正在读取节气与节日数据"
        case .usingFallback:
            "远程日期知识暂不可用，当前使用本地规则"
        case .usingCache:
            "当前使用最近一次有效的日期知识数据"
        case .unavailable:
            "节气与节日数据暂不可用"
        }
    }
}

@MainActor
protocol DateKnowledgeRepositoryProtocol {
    var lastLoadState: DateKnowledgeLoadState { get }
    func snapshot(for year: Int) async throws -> DateKnowledgeYearSnapshot
}

extension DateKnowledgeRepositoryProtocol {
    var lastLoadState: DateKnowledgeLoadState { .available }
}

/// Resolves one primary label while keeping every candidate for the detail page.
struct DayAnnotationResolver: Sendable {
    func resolve(
        dayID: DayID,
        holidayRecord: HolidayRecord? = nil,
        knowledgeAnnotations: [DayAnnotation] = [],
        specialDays: [SpecialDay] = [],
        holidayProviderID: String = "official",
        holidaySourceURL: URL? = nil
    ) -> (primary: DayAnnotation?, candidates: [DayAnnotation]) {
        var candidates = knowledgeAnnotations.filter { $0.dayID == dayID }

        if let holidayRecord {
            let kind: DayAnnotationKind = holidayRecord.kind == .makeupWorkday
                ? .makeupWorkday
                : .publicHoliday
            candidates.append(
                DayAnnotation(
                    dayID: dayID,
                    title: holidayRecord.name,
                    kind: kind,
                    sourceID: holidayProviderID,
                    sourceURL: holidaySourceURL
                )
            )
        }

        candidates.append(contentsOf: specialDays.compactMap { specialDay in
            guard specialDay.resolvedDay(for: dayID.year) == dayID else {
                return nil
            }

            return DayAnnotation(
                dayID: dayID,
                title: specialDay.title,
                kind: .observance,
                sourceID: "local.special-day"
            )
        })

        let uniqueCandidates = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted(by: sort)

        return (uniqueCandidates.first, Array(uniqueCandidates))
    }

    private func sort(_ lhs: DayAnnotation, _ rhs: DayAnnotation) -> Bool {
        if lhs.kind.displayPriority != rhs.kind.displayPriority {
            return lhs.kind.displayPriority < rhs.kind.displayPriority
        }
        let sourceOrder = lhs.sourceID.localizedStandardCompare(rhs.sourceID)
        if sourceOrder != .orderedSame {
            return sourceOrder == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
