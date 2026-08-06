import Foundation

enum HTTPClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse(statusCode: Int)
    case networkUnavailable
    case timedOut
    case cancelled
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode):
            "网络服务返回了无效响应（HTTP \(statusCode)）"
        case .networkUnavailable:
            "网络服务暂时无法连接"
        case .timedOut:
            "网络请求超时"
        case .cancelled:
            "网络请求已取消"
        case .decodingFailed:
            "网络响应数据无法解码"
        }
    }
}

/// A small URLSession boundary shared by remote data providers.
struct HTTPClient: Sendable {
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 15
    ) {
        self.session = session
        self.timeoutInterval = max(timeoutInterval, 1)
    }

    func get<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from url: URL
    ) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await send(request, decoding: type)
    }

    func send<Value: Decodable & Sendable>(
        _ request: URLRequest,
        decoding type: Value.Type
    ) async throws -> Value {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse(statusCode: -1)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw HTTPClientError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(Value.self, from: data)
            } catch {
                throw HTTPClientError.decodingFailed
            }
        } catch let error as HTTPClientError {
            throw error
        } catch is CancellationError {
            throw HTTPClientError.cancelled
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw HTTPClientError.networkUnavailable
        }
    }

    private static func map(_ error: URLError) -> HTTPClientError {
        switch error.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .dataNotAllowed:
            .networkUnavailable
        default:
            .networkUnavailable
        }
    }
}
