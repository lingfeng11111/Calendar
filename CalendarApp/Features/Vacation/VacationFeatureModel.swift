import Foundation
import Observation

enum VacationDataState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
final class VacationFeatureModel {
    @ObservationIgnored let repository: (any VacationRepositoryProtocol)?

    let year: Int
    var dataState: VacationDataState = .idle
    var vacationPeriods: [VacationPeriod] = []
    var specialDays: [SpecialDay] = []
    var errorMessage: String?

    init(
        repository: (any VacationRepositoryProtocol)?,
        initialYear: Int = DayID(Date()).year
    ) {
        self.repository = repository
        self.year = initialYear
    }

    var isEmpty: Bool {
        vacationPeriods.isEmpty && specialDays.isEmpty
    }

    func load() {
        guard !Task.isCancelled else {
            return
        }

        dataState = .loading
        errorMessage = nil

        do {
            let snapshot = try repository?.snapshot(for: year) ?? PersonalDateFixtures.sample
            vacationPeriods = snapshot.vacationPeriods
            specialDays = snapshot.specialDays
            dataState = .loaded
        } catch let error as VacationRepositoryError {
            dataState = .failed
            errorMessage = error.localizedDescription
        } catch {
            dataState = .failed
            errorMessage = "个人日期暂不可用"
        }
    }

    func retry() {
        load()
    }

    func save(period: VacationPeriod) throws {
        if let repository {
            try repository.save(period: period)
        } else {
            vacationPeriods.removeAll { $0.id == period.id }
            vacationPeriods.append(period)
            vacationPeriods.sort {
                if $0.startDay != $1.startDay {
                    return $0.startDay < $1.startDay
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            dataState = .loaded
            return
        }

        load()
    }

    func save(specialDay: SpecialDay) throws {
        if let repository {
            try repository.save(specialDay: specialDay)
        } else {
            specialDays.removeAll { $0.id == specialDay.id }
            specialDays.append(specialDay)
            specialDays.sort {
                let leftDay = $0.resolvedDay(for: year) ?? $0.anchorDay
                let rightDay = $1.resolvedDay(for: year) ?? $1.anchorDay
                if leftDay != rightDay {
                    return leftDay < rightDay
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            dataState = .loaded
            return
        }

        load()
    }

    func delete(period: VacationPeriod) throws {
        if let repository {
            try repository.deleteVacationPeriod(id: period.id)
        } else {
            vacationPeriods.removeAll { $0.id == period.id }
            dataState = .loaded
            return
        }

        load()
    }

    func delete(specialDay: SpecialDay) throws {
        if let repository {
            try repository.deleteSpecialDay(id: specialDay.id)
        } else {
            specialDays.removeAll { $0.id == specialDay.id }
            dataState = .loaded
            return
        }

        load()
    }
}
