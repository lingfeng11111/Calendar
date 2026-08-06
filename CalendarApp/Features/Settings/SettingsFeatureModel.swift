import Observation

enum SettingsSystemCalendarState: Equatable, Sendable {
    case idle
    case requesting
    case ready
    case unavailable
}

@MainActor
@Observable
final class SettingsFeatureModel {
    @ObservationIgnored let systemCalendarService: (any SystemCalendarServiceProtocol)?

    var systemCalendarAccess: SystemCalendarAccess
    var systemCalendarState: SettingsSystemCalendarState = .idle
    var errorMessage: String?

    init(systemCalendarService: (any SystemCalendarServiceProtocol)?) {
        self.systemCalendarService = systemCalendarService
        self.systemCalendarAccess = systemCalendarService?.access ?? .unavailable
    }

    func refreshSystemCalendarAccess() {
        guard let systemCalendarService else {
            systemCalendarAccess = .unavailable
            systemCalendarState = .unavailable
            return
        }

        systemCalendarAccess = systemCalendarService.access
        systemCalendarState = .ready
    }

    func requestSystemCalendarReadAccess() async {
        guard let systemCalendarService else {
            systemCalendarAccess = .unavailable
            systemCalendarState = .unavailable
            errorMessage = "系统日历服务尚未准备好"
            return
        }

        errorMessage = nil
        systemCalendarState = .requesting
        systemCalendarAccess = await systemCalendarService.requestReadAccess()
        systemCalendarState = .ready
    }
}
