import Foundation

@MainActor
protocol HolidayRepositoryProtocol {
    func snapshot(for year: Int) async throws -> HolidayYearSnapshot

    func refresh(year: Int) async throws -> HolidayYearSnapshot

    func refreshWindow(referenceDate: Date?) async throws -> HolidayRefreshReport
}

enum HolidayRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidYear(Int)
    case notPublished(Int)
    case providersUnavailable(
        primary: HolidayProviderError,
        backup: HolidayProviderError?
    )
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case let .invalidYear(year):
            return "无效的公历年份：\(year)"
        case let .notPublished(year):
            return "\(year) 年官方节假日安排尚未发布"
        case let .providersUnavailable(primary, backup):
            if let backup {
                return "节假日主数据源和备用数据源均不可用：\(primary.localizedDescription)，\(backup.localizedDescription)"
            }
            return "节假日数据源不可用：\(primary.localizedDescription)"
        case .persistenceFailed:
            return "节假日缓存保存或读取失败"
        }
    }
}

enum HolidayCacheError: Error, Equatable, LocalizedError, Sendable {
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "节假日缓存记录无法转换为领域数据"
        }
    }
}
