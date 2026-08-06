import Foundation
import SwiftData

struct PersonalDateSnapshot: Equatable, Sendable {
    let year: Int
    let vacationPeriods: [VacationPeriod]
    let specialDays: [SpecialDay]
}

@MainActor
protocol VacationRepositoryProtocol {
    func snapshot(for year: Int) throws -> PersonalDateSnapshot
    func save(period: VacationPeriod) throws
    func save(specialDay: SpecialDay) throws
    func deleteVacationPeriod(id: UUID) throws
    func deleteSpecialDay(id: UUID) throws
}

@MainActor
extension VacationRepositoryProtocol {
    func save(period: VacationPeriod) throws {
        throw VacationRepositoryError.persistenceFailed
    }

    func save(specialDay: SpecialDay) throws {
        throw VacationRepositoryError.persistenceFailed
    }

    func deleteVacationPeriod(id: UUID) throws {
        throw VacationRepositoryError.persistenceFailed
    }

    func deleteSpecialDay(id: UUID) throws {
        throw VacationRepositoryError.persistenceFailed
    }
}

enum VacationRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case invalidModel
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            "无效的公历年份：\(year)"
        case .invalidModel:
            "个人日期数据无法转换"
        case .persistenceFailed:
            "个人日期数据保存或读取失败"
        }
    }
}

@MainActor
final class VacationRepository: VacationRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot(for year: Int) throws -> PersonalDateSnapshot {
        guard (1...9999).contains(year) else {
            throw VacationRepositoryError.invalidYear(year)
        }

        do {
            let periods = try modelContext
                .fetch(FetchDescriptor<VacationPeriodModel>())
                .compactMap { try $0.makeDomain() }
                .filter { $0.overlaps(year: year) }
                .sorted {
                    if $0.startDay != $1.startDay {
                        return $0.startDay < $1.startDay
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            let specialDays = try modelContext
                .fetch(FetchDescriptor<SpecialDayModel>())
                .compactMap { try $0.makeDomain() }
                .filter { $0.isVisible(in: year) }
                .sorted {
                    let leftDay = $0.resolvedDay(for: year) ?? $0.anchorDay
                    let rightDay = $1.resolvedDay(for: year) ?? $1.anchorDay
                    if leftDay != rightDay {
                        return leftDay < rightDay
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            return PersonalDateSnapshot(
                year: year,
                vacationPeriods: periods,
                specialDays: specialDays
            )
        } catch let error as VacationRepositoryError {
            throw error
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func save(period: VacationPeriod) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<VacationPeriodModel>())
            if let model = models.first(where: { $0.id == period.id }) {
                model.update(from: period)
            } else {
                modelContext.insert(VacationPeriodModel(period: period))
            }
            try modelContext.save()
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func save(specialDay: SpecialDay) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<SpecialDayModel>())
            if let model = models.first(where: { $0.id == specialDay.id }) {
                model.update(from: specialDay)
            } else {
                modelContext.insert(SpecialDayModel(specialDay: specialDay))
            }
            try modelContext.save()
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func deleteVacationPeriod(id: UUID) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<VacationPeriodModel>())
            if let model = models.first(where: { $0.id == id }) {
                modelContext.delete(model)
                try modelContext.save()
            }
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func deleteSpecialDay(id: UUID) throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<SpecialDayModel>())
            if let model = models.first(where: { $0.id == id }) {
                modelContext.delete(model)
                try modelContext.save()
            }
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func resetForTesting() throws {
        do {
            try modelContext.fetch(FetchDescriptor<VacationPeriodModel>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<SpecialDayModel>()).forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }

    func seedIfEmpty(with snapshot: PersonalDateSnapshot) throws {
        do {
            let hasPeriods = try !modelContext.fetch(FetchDescriptor<VacationPeriodModel>()).isEmpty
            let hasSpecialDays = try !modelContext.fetch(FetchDescriptor<SpecialDayModel>()).isEmpty
            guard !hasPeriods, !hasSpecialDays else {
                return
            }

            snapshot.vacationPeriods.forEach { modelContext.insert(VacationPeriodModel(period: $0)) }
            snapshot.specialDays.forEach { modelContext.insert(SpecialDayModel(specialDay: $0)) }
            try modelContext.save()
        } catch {
            throw VacationRepositoryError.persistenceFailed
        }
    }
}

enum PersonalDateFixtures {
    static var sample: PersonalDateSnapshot {
        let winterStart = DayID(year: 2026, month: 1, day: 24)!
        let winterEnd = DayID(year: 2026, month: 2, day: 20)!
        let annualStart = DayID(year: 2026, month: 4, day: 6)!
        let annualEnd = DayID(year: 2026, month: 4, day: 10)!
        let birthdayAnchor = DayID(year: 2000, month: 10, day: 18)!
        let appointmentDay = DayID(year: 2026, month: 6, day: 1)!

        return PersonalDateSnapshot(
            year: 2026,
            vacationPeriods: [
                try! VacationPeriod(
                    id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
                    title: "寒假",
                    kind: .winter,
                    startDay: winterStart,
                    endDay: winterEnd,
                    color: .teal
                ),
                try! VacationPeriod(
                    id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
                    title: "四月年假",
                    kind: .annualLeave,
                    startDay: annualStart,
                    endDay: annualEnd,
                    color: .blue,
                    note: "五天"
                )
            ],
            specialDays: [
                try! SpecialDay(
                    id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
                    title: "生日",
                    anchorDay: birthdayAnchor,
                    recurrence: .yearlyGregorian,
                    color: .purple
                ),
                try! SpecialDay(
                    id: UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!,
                    title: "年度体检",
                    anchorDay: appointmentDay,
                    recurrence: .none,
                    color: .orange
                )
            ]
        )
    }
}
