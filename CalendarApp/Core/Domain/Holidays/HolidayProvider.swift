import Foundation

/// The replaceable boundary for yearly holiday data sources.
protocol HolidayProvider: Sendable {
    var id: String { get }

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot
}

enum HolidayProviderError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case invalidRequest
    case networkUnavailable
    case rateLimited
    case invalidResponse(statusCode: Int)
    case decodingFailed
    case dataValidationFailed
    case permissionDenied
    case persistenceFailed
    case notPublished

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            "无效的公历年份：\(year)"
        case .invalidRequest:
            "节假日请求无效"
        case .networkUnavailable:
            "节假日服务暂时无法连接"
        case .rateLimited:
            "节假日服务请求过于频繁"
        case let .invalidResponse(statusCode):
            "节假日服务返回了无效响应（HTTP \(statusCode)）"
        case .decodingFailed:
            "节假日服务数据格式无法识别"
        case .dataValidationFailed:
            "节假日服务数据未通过校验"
        case .permissionDenied:
            "节假日服务访问被拒绝"
        case .persistenceFailed:
            "节假日数据保存失败"
        case .notPublished:
            "该年度官方节假日安排尚未发布"
        }
    }
}
