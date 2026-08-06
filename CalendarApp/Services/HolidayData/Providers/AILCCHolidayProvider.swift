import Foundation

/// A replaceable backup provider backed by AILCC's batch holiday API.
struct AILCCHolidayProvider: HolidayProvider, Sendable {
    static let defaultBaseURL = URL(string: "https://holiday.ailcc.com/api/holiday")!

    private static let maxDatesPerRequest = 50

    let id: String
    let baseURL: URL
    let client: HTTPClient

    private let now: @Sendable () -> Date

    init(
        baseURL: URL = Self.defaultBaseURL,
        client: HTTPClient = HTTPClient(),
        id: String = "ailcc",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.client = client
        self.id = id
        self.now = now
    }

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot {
        guard (1...9999).contains(year) else {
            throw HolidayProviderError.invalidYear(year)
        }

        do {
            let dates = try dates(for: year)
            var records: [HolidayRecord] = []
            var sourceURL: URL?

            for start in stride(
                from: 0,
                to: dates.count,
                by: Self.maxDatesPerRequest
            ) {
                let end = min(start + Self.maxDatesPerRequest, dates.count)
                let batchDates = Array(dates[start..<end])
                let url = try batchEndpoint(for: batchDates)
                sourceURL = sourceURL ?? url

                let response = try await client.get(
                    AILCCBatchResponseDTO.self,
                    from: url
                )

                guard response.code == 0 else {
                    throw HolidayProviderError.dataValidationFailed
                }

                records.append(contentsOf: try response.makeRecords(for: year))
            }

            guard !records.isEmpty else {
                throw HolidayProviderError.notPublished
            }

            do {
                return try HolidayYearSnapshot(
                    year: year,
                    providerID: id,
                    fetchedAt: now(),
                    sourceURL: sourceURL,
                    records: records
                )
            } catch {
                throw HolidayProviderError.dataValidationFailed
            }
        } catch let error as HolidayProviderError {
            throw error
        } catch let error as HTTPClientError {
            if case .cancelled = error {
                throw CancellationError()
            }

            throw Self.map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HolidayProviderError.dataValidationFailed
        }
    }

    func batchEndpoint(for dates: [String]) throws -> URL {
        guard !dates.isEmpty,
              dates.count <= Self.maxDatesPerRequest else {
            throw HolidayProviderError.invalidRequest
        }

        guard baseURL.scheme != nil, baseURL.host != nil else {
            throw HolidayProviderError.invalidRequest
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("batch"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "d", value: dates.joined(separator: ",")),
            URLQueryItem(name: "type", value: "Y")
        ]

        guard let url = components?.url else {
            throw HolidayProviderError.invalidRequest
        }

        return url
    }

    private func dates(for year: Int) throws -> [String] {
        guard let firstDay = DayID(year: year, month: 1, day: 1) else {
            throw HolidayProviderError.invalidYear(year)
        }

        let nextYearDay = year == 9999
            ? nil
            : DayID(year: year + 1, month: 1, day: 1)
        var day = firstDay
        var values: [String] = []

        for _ in 0..<366 where day.year == year {
            values.append(day.description)
            day = day.adding(days: 1)

            if let nextYearDay, day >= nextYearDay {
                break
            }
        }

        return values
    }

    private static func map(_ error: HTTPClientError) -> HolidayProviderError {
        switch error {
        case let .invalidResponse(statusCode):
            switch statusCode {
            case 404:
                .notPublished
            case 401, 403:
                .permissionDenied
            case 429:
                .rateLimited
            default:
                .invalidResponse(statusCode: statusCode)
            }
        case .networkUnavailable, .timedOut:
            .networkUnavailable
        case .cancelled:
            .networkUnavailable
        case .decodingFailed:
            .decodingFailed
        }
    }
}

private extension AILCCBatchResponseDTO {
    func makeRecords(for year: Int) throws -> [HolidayRecord] {
        var records: [HolidayRecord] = []

        if !type.isEmpty {
            for (date, descriptor) in type {
                guard [2, 3, 4].contains(descriptor.type) else {
                    continue
                }

                guard let dayID = Self.makeDayID(from: date), dayID.year == year else {
                    throw HolidayDataError.invalidDate(date)
                }

                let fallbackName = holiday[date]??.name ?? descriptor.name
                let name = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw HolidayDataError.emptyName(dayID)
                }

                let kind: HolidayRecordKind = descriptor.type == 4
                    ? .makeupWorkday
                    : .holiday
                records.append(HolidayRecord(dayID: dayID, name: name, kind: kind))
            }
        } else {
            for (date, value) in holiday {
                guard let value, value.holiday else {
                    continue
                }

                guard let dayID = Self.makeDayID(from: date), dayID.year == year else {
                    throw HolidayDataError.invalidDate(date)
                }

                let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw HolidayDataError.emptyName(dayID)
                }

                records.append(
                    HolidayRecord(dayID: dayID, name: name, kind: .holiday)
                )
            }
        }

        return records
    }

    static func makeDayID(from value: String) -> DayID? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return DayID(year: year, month: month, day: day)
    }
}
