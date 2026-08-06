import Foundation
import SwiftData

@MainActor
final class HolidayRepository: HolidayRepositoryProtocol {
    private struct CachedSnapshot {
        let snapshot: HolidayYearSnapshot
        let cachedAt: Date
    }

    private let modelContext: ModelContext
    private let primaryProvider: any HolidayProvider
    private let backupProvider: (any HolidayProvider)?
    private let refreshPolicy: HolidayRefreshPolicy
    private let now: @Sendable () -> Date

    init(
        modelContext: ModelContext,
        primaryProvider: any HolidayProvider,
        backupProvider: (any HolidayProvider)? = nil,
        cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60,
        nextYearCacheMaxAge: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContext = modelContext
        self.primaryProvider = primaryProvider
        self.backupProvider = backupProvider
        self.refreshPolicy = HolidayRefreshPolicy(
            regularCacheAge: cacheMaxAge,
            nextYearCacheAge: nextYearCacheMaxAge
        )
        self.now = now
    }

    func snapshot(for year: Int) async throws -> HolidayYearSnapshot {
        try validate(year: year)

        if let cached = try cachedSnapshot(for: year), !refreshPolicy.shouldRefresh(
            year: year,
            cachedAt: cached.cachedAt,
            referenceDate: now()
        ) {
            return cached.snapshot
        }

        return try await refresh(year: year)
    }

    func refresh(year: Int) async throws -> HolidayYearSnapshot {
        try validate(year: year)
        let cached = try cachedSnapshot(for: year)

        do {
            let snapshot = try await fetch(from: primaryProvider, year: year)
            try save(snapshot)
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch let primaryError as HolidayProviderError {
            if let backupProvider {
                do {
                    let snapshot = try await fetch(from: backupProvider, year: year)
                    try save(snapshot)
                    return snapshot
                } catch is CancellationError {
                    throw CancellationError()
                } catch is HolidayRepositoryError {
                    throw HolidayRepositoryError.persistenceFailed
                } catch let backupError as HolidayProviderError {
                    if let cached {
                        return cached.snapshot
                    }

                    throw repositoryError(
                        year: year,
                        primary: primaryError,
                        backup: backupError
                    )
                } catch {
                    if let cached {
                        return cached.snapshot
                    }

                    throw repositoryError(
                        year: year,
                        primary: primaryError,
                        backup: .dataValidationFailed
                    )
                }
            }

            if let cached {
                return cached.snapshot
            }

            throw repositoryError(year: year, primary: primaryError, backup: nil)
        } catch is HolidayRepositoryError {
            throw HolidayRepositoryError.persistenceFailed
        } catch {
            throw HolidayRepositoryError.providersUnavailable(
                primary: .dataValidationFailed,
                backup: nil
            )
        }
    }

    func refreshWindow(referenceDate: Date? = nil) async throws -> HolidayRefreshReport {
        let date = referenceDate ?? now()
        let window = refreshPolicy.window(for: date)
        var states: [Int: HolidayYearRefreshState] = [:]

        for year in window.years {
            do {
                states[year] = .available(try await refresh(year: year))
            } catch let error as HolidayRepositoryError {
                switch error {
                case .notPublished:
                    states[year] = .notPublished
                case .providersUnavailable:
                    states[year] = .unavailable
                case .invalidYear, .persistenceFailed:
                    throw error
                }
            }
        }

        return HolidayRefreshReport(window: window, states: states)
    }

    private func fetch(
        from provider: any HolidayProvider,
        year: Int
    ) async throws -> HolidayYearSnapshot {
        do {
            let snapshot = try await provider.fetchYear(year)
            guard snapshot.year == year else {
                throw HolidayProviderError.dataValidationFailed
            }

            return snapshot
        } catch let error as HolidayProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HolidayProviderError.dataValidationFailed
        }
    }

    private func validate(year: Int) throws {
        guard (1...9999).contains(year) else {
            throw HolidayRepositoryError.invalidYear(year)
        }
    }

    private func cachedSnapshot(for year: Int) throws -> CachedSnapshot? {
        do {
            let models = try modelContext.fetch(FetchDescriptor<HolidaySnapshotModel>())
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
            throw HolidayRepositoryError.persistenceFailed
        }
    }

    private func save(_ snapshot: HolidayYearSnapshot) throws {
        let timestamp = now()

        do {
            if let existing = try modelContext.fetch(FetchDescriptor<HolidaySnapshotModel>())
                .first(where: { $0.year == snapshot.year }) {
                let oldRecords = existing.records
                oldRecords.forEach(modelContext.delete)
                existing.replace(with: snapshot, cachedAt: timestamp)
                existing.records.forEach(modelContext.insert)
            } else {
                let model = HolidaySnapshotModel(snapshot: snapshot, cachedAt: timestamp)
                modelContext.insert(model)
                model.records.forEach(modelContext.insert)
            }

            try modelContext.save()
        } catch let error as HolidayRepositoryError {
            throw error
        } catch {
            throw HolidayRepositoryError.persistenceFailed
        }
    }

    private func repositoryError(
        year: Int,
        primary: HolidayProviderError,
        backup: HolidayProviderError?
    ) -> HolidayRepositoryError {
        if primary == .notPublished,
           backup == nil || backup == .notPublished {
            return .notPublished(year)
        }

        return .providersUnavailable(primary: primary, backup: backup)
    }
}
