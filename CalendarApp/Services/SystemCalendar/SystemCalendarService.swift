import EventKit
import Foundation

@MainActor
protocol SystemCalendarServiceProtocol {
    var access: SystemCalendarAccess { get }

    func requestReadAccess() async -> SystemCalendarAccess
    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>?
    ) async throws -> [SystemCalendarEventSnapshot]
}

@MainActor
final class EventKitSystemCalendarService: SystemCalendarServiceProtocol {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var access: SystemCalendarAccess {
        Self.mapAccess(EKEventStore.authorizationStatus(for: .event))
    }

    func requestReadAccess() async -> SystemCalendarAccess {
        guard access == .notDetermined else {
            return access
        }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            eventStore.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        if granted, access == .notDetermined {
            return .fullAccess
        }
        return access
    }

    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>? = nil
    ) async throws -> [SystemCalendarEventSnapshot] {
        guard interval.start <= interval.end else {
            throw SystemCalendarServiceError.invalidDateRange
        }

        switch access {
        case .fullAccess:
            break
        case .restricted:
            throw SystemCalendarServiceError.accessRestricted
        case .unavailable, .notDetermined, .denied, .writeOnly:
            throw SystemCalendarServiceError.permissionDenied
        }

        let calendars = eventStore.calendars(for: .event).filter { calendar in
            guard let calendarIDs, !calendarIDs.isEmpty else {
                return true
            }

            return calendarIDs.contains(calendar.calendarIdentifier)
        }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: calendars
        )

        return eventStore
            .events(matching: predicate)
            .compactMap(Self.makeSnapshot)
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }
                return $0.id < $1.id
            }
    }

    private static func mapAccess(_ status: EKAuthorizationStatus) -> SystemCalendarAccess {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .writeOnly:
            .writeOnly
        case .fullAccess:
            .fullAccess
        @unknown default:
            .unavailable
        }
    }

    private static func makeSnapshot(from event: EKEvent) -> SystemCalendarEventSnapshot? {
        guard let startDate = event.startDate,
              let endDate = event.endDate,
              let calendar = event.calendar else {
            return nil
        }

        let externalIdentifier = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        let calendarItemIdentifier = event.calendarItemIdentifier
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = event.calendar.source?.title
        let recurrenceDescription = event.recurrenceRules?.first.map(recurrenceDescription)

        return SystemCalendarEventSnapshot(
            externalIdentifier: externalIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            title: title.isEmpty ? "未命名日程" : title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZone?.identifier,
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            sourceTitle: sourceTitle,
            recurrenceDescription: recurrenceDescription,
            note: event.notes
        )
    }

    private static func recurrenceDescription(_ rule: EKRecurrenceRule) -> String {
        let unit: String
        switch rule.frequency {
        case .daily:
            unit = "天"
        case .weekly:
            unit = "周"
        case .monthly:
            unit = "月"
        case .yearly:
            unit = "年"
        @unknown default:
            unit = "周期"
        }

        return rule.interval == 1 ? "每\(unit)" : "每\(rule.interval)\(unit)"
    }
}
