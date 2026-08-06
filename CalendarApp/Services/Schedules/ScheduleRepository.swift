import Foundation
import SwiftData

struct ScheduleSnapshot: Equatable, Sendable {
    let year: Int
    let items: [ScheduleItem]
}

@MainActor
protocol ScheduleRepositoryProtocol {
    func snapshot(for year: Int) throws -> ScheduleSnapshot
    func search(_ query: ScheduleQuery, in year: Int) throws -> [ScheduleItem]
    func save(_ schedule: ScheduleItem) throws
    func delete(id: UUID) throws
}

@MainActor
extension ScheduleRepositoryProtocol {
    func search(_ query: ScheduleQuery, in year: Int) throws -> [ScheduleItem] {
        try snapshot(for: year).items.filter(query.matches)
    }

    func save(_ schedule: ScheduleItem) throws {
        throw ScheduleRepositoryError.persistenceFailed
    }

    func delete(id: UUID) throws {
        throw ScheduleRepositoryError.persistenceFailed
    }
}

enum ScheduleRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case invalidModel
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            "无效的公历年份：\(year)"
        case .invalidModel:
            "本地日程数据无法转换"
        case .persistenceFailed:
            "本地日程保存或读取失败"
        }
    }
}

@MainActor
final class ScheduleRepository: ScheduleRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot(for year: Int) throws -> ScheduleSnapshot {
        guard (1...9999).contains(year) else {
            throw ScheduleRepositoryError.invalidYear(year)
        }

        do {
            let items = try modelContext
                .fetch(FetchDescriptor<LocalScheduleItemModel>())
                .compactMap { try $0.makeDomain() }
                .filter { $0.overlaps(year: year) }
                .sorted {
                    if $0.startDate != $1.startDate {
                        return $0.startDate < $1.startDate
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            return ScheduleSnapshot(year: year, items: items)
        } catch let error as ScheduleRepositoryError {
            throw error
        } catch {
            throw ScheduleRepositoryError.persistenceFailed
        }
    }

    func search(_ query: ScheduleQuery, in year: Int) throws -> [ScheduleItem] {
        try snapshot(for: year).items.filter(query.matches)
    }

    func save(_ schedule: ScheduleItem) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<LocalScheduleItemModel>())
            if let model = models.first(where: { $0.id == schedule.id }) {
                model.update(from: schedule)
            } else {
                modelContext.insert(LocalScheduleItemModel(schedule: schedule))
            }
            try modelContext.save()
        } catch {
            throw ScheduleRepositoryError.persistenceFailed
        }
    }

    func delete(id: UUID) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<LocalScheduleItemModel>())
            if let model = models.first(where: { $0.id == id }) {
                modelContext.delete(model)
                try modelContext.save()
            }
        } catch {
            throw ScheduleRepositoryError.persistenceFailed
        }
    }

    func resetForTesting() throws {
        do {
            try modelContext
                .fetch(FetchDescriptor<LocalScheduleItemModel>())
                .forEach { modelContext.delete($0) }
            try modelContext.save()
        } catch {
            throw ScheduleRepositoryError.persistenceFailed
        }
    }

    func seedIfEmpty(with snapshot: ScheduleSnapshot) throws {
        do {
            guard try modelContext.fetch(FetchDescriptor<LocalScheduleItemModel>()).isEmpty else {
                return
            }

            snapshot.items.forEach { modelContext.insert(LocalScheduleItemModel(schedule: $0)) }
            try modelContext.save()
        } catch {
            throw ScheduleRepositoryError.persistenceFailed
        }
    }
}

enum ScheduleFixtures {
    static var sample: ScheduleSnapshot {
        let reviewDay = DayID(year: 2026, month: 8, day: 6)!
        let reviewStart = reviewDay.date!.addingTimeInterval(9 * 60 * 60)
        let reviewEnd = reviewDay.date!.addingTimeInterval(10 * 60 * 60)
        let readingDay = DayID(year: 2026, month: 8, day: 6)!
        let readingStart = readingDay.date!.addingTimeInterval(20 * 60 * 60)
        let readingEnd = readingDay.date!.addingTimeInterval(20 * 60 * 60 + 30 * 60)
        let readingUntil = DayID(year: 2026, month: 8, day: 12)!.date!.addingTimeInterval(23 * 60 * 60 + 59 * 60)
        let travelStart = DayID(year: 2026, month: 8, day: 20)!
        let travelEnd = DayID(year: 2026, month: 8, day: 22)!

        return ScheduleSnapshot(
            year: 2026,
            items: [
                try! ScheduleItem(
                    id: UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!,
                    title: "项目评审",
                    startDate: reviewStart,
                    endDate: reviewEnd,
                    color: .blue,
                    note: "准备月度进度和风险清单"
                ),
                try! ScheduleItem(
                    id: UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!,
                    title: "晚间阅读",
                    startDate: readingStart,
                    endDate: readingEnd,
                    recurrence: .daily,
                    repeatUntil: readingUntil,
                    color: .purple
                ),
                try! ScheduleItem(
                    id: UUID(uuidString: "D0000000-0000-0000-0000-000000000003")!,
                    title: "周末短途旅行",
                    startDate: travelStart.date!,
                    endDate: travelEnd.date!,
                    isAllDay: true,
                    color: .teal
                )
            ]
        )
    }
}
