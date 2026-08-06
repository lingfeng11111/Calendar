import Foundation

/// The primary provider backed by the holiday-cn yearly JSON files.
struct HolidayCNProvider: HolidayProvider, Sendable {
    static let defaultBaseURL = URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master")!

    let id: String
    let baseURL: URL
    let client: HTTPClient

    private let now: @Sendable () -> Date

    init(
        baseURL: URL = Self.defaultBaseURL,
        client: HTTPClient = HTTPClient(),
        id: String = "holiday-cn",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.client = client
        self.id = id
        self.now = now
    }

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot {
        let url = try endpoint(for: year)

        do {
            let dto = try await client.get(HolidayCNYearDTO.self, from: url)

            guard dto.year == year else {
                throw HolidayProviderError.dataValidationFailed
            }

            do {
                return try dto.makeSnapshot(
                    providerID: id,
                    fetchedAt: now(),
                    sourceURL: url
                )
            } catch is HolidayDataError {
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

    func endpoint(for year: Int) throws -> URL {
        guard (1...9999).contains(year) else {
            throw HolidayProviderError.invalidYear(year)
        }

        guard baseURL.scheme != nil, baseURL.host != nil else {
            throw HolidayProviderError.invalidRequest
        }

        return baseURL.appendingPathComponent("\(year).json")
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
