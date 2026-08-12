import Foundation
import UserNotifications

@MainActor
protocol NotificationServiceProtocol {
    func authorizationStatus() async -> CalendarNotificationAuthorization
    func requestAuthorization() async -> CalendarNotificationAuthorization
    func reconcile(_ requests: [CalendarNotificationRequest]) async throws
}

@MainActor
final class UserNotificationsService: NotificationServiceProtocol {
    private static let identifierPrefix = "calendarapp.notification."

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func authorizationStatus() async -> CalendarNotificationAuthorization {
        await withCheckedContinuation { (continuation: CheckedContinuation<CalendarNotificationAuthorization, Never>) in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: Self.mapAuthorizationStatus(settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization() async -> CalendarNotificationAuthorization {
        let currentStatus = await authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        return await authorizationStatus()
    }

    func reconcile(_ requests: [CalendarNotificationRequest]) async throws {
        let authorization = await authorizationStatus()
        if !authorization.canSchedule {
            switch authorization {
            case .unavailable:
                throw CalendarNotificationServiceError.unavailable
            case .notDetermined, .denied:
                throw CalendarNotificationServiceError.permissionDenied
            case .authorized, .provisional, .ephemeral:
                return
            }
        }

        let requestIDs = requests.map(\.id)
        guard Set(requestIDs).count == requestIDs.count else {
            throw CalendarNotificationServiceError.schedulingFailed
        }

        let identifierPrefix = Self.identifierPrefix
        let ownedIdentifiers = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: requests
                        .map(\.identifier)
                        .filter { $0.hasPrefix(identifierPrefix) }
                )
            }
        }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.threadIdentifier = request.kind.rawValue

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: request.date
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )
            let notificationRequest = UNNotificationRequest(
                identifier: Self.identifier(for: request.id),
                content: content,
                trigger: trigger
            )

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    notificationCenter.add(notificationRequest) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            } catch {
                throw CalendarNotificationServiceError.schedulingFailed
            }
        }
    }

    private static func identifier(for requestID: String) -> String {
        "\(identifierPrefix)\(requestID)"
    }

    private nonisolated static func mapAuthorizationStatus(
        _ status: UNAuthorizationStatus
    ) -> CalendarNotificationAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
final class FixtureNotificationService: NotificationServiceProtocol {
    var authorization: CalendarNotificationAuthorization
    private(set) var authorizationRequestCount = 0
    private(set) var reconciledPlans: [[CalendarNotificationRequest]] = []

    init(authorization: CalendarNotificationAuthorization = .notDetermined) {
        self.authorization = authorization
    }

    func authorizationStatus() async -> CalendarNotificationAuthorization {
        authorization
    }

    func requestAuthorization() async -> CalendarNotificationAuthorization {
        authorizationRequestCount += 1
        if authorization == .notDetermined {
            authorization = .authorized
        }
        return authorization
    }

    func reconcile(_ requests: [CalendarNotificationRequest]) async throws {
        if !authorization.canSchedule {
            switch authorization {
            case .unavailable:
                throw CalendarNotificationServiceError.unavailable
            case .notDetermined, .denied:
                throw CalendarNotificationServiceError.permissionDenied
            case .authorized, .provisional, .ephemeral:
                return
            }
        }
        reconciledPlans.append(requests)
    }
}
