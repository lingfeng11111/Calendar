import EventKit
import Foundation
import SwiftData

private final class SystemCalendarChangeObserver: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    func cancel() {
        NotificationCenter.default.removeObserver(token)
    }
}

@MainActor
protocol SystemCalendarServiceProtocol {
    var access: SystemCalendarAccess { get }

    func requestReadAccess() async -> SystemCalendarAccess
    func requestWriteAccess() async -> SystemCalendarAccess
    func changes() -> AsyncStream<SystemCalendarChange>
    func calendars() async throws -> [SystemCalendarDescriptor]
    func writableCalendars() async throws -> [SystemCalendarDescriptor]
    func createEvent(_ draft: SystemCalendarEventDraft, calendarID: String) async throws
    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>?
    ) async throws -> [SystemCalendarEventSnapshot]
}

@MainActor
protocol SystemCalendarSelectionStoreProtocol {
    func selectedCalendarIDs() throws -> Set<String>?
    func save(selectedCalendarIDs: Set<String>?) throws
}

enum SystemCalendarSelectionStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidStoredValue
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            "系统日历来源设置无法读取"
        case .persistenceFailed:
            "系统日历来源设置无法保存"
        }
    }
}

@MainActor
final class SwiftDataSystemCalendarSelectionStore: SystemCalendarSelectionStoreProtocol {
    static let preferenceKey = "systemCalendar.selectedCalendarIDs"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func selectedCalendarIDs() throws -> Set<String>? {
        do {
            guard let preference = try preferenceModel() else {
                return nil
            }

            guard let data = preference.value.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                throw SystemCalendarSelectionStoreError.invalidStoredValue
            }
            return Set(ids)
        } catch let error as SystemCalendarSelectionStoreError {
            throw error
        } catch {
            throw SystemCalendarSelectionStoreError.persistenceFailed
        }
    }

    func save(selectedCalendarIDs: Set<String>?) throws {
        do {
            let preference = try preferenceModel()

            guard let selectedCalendarIDs else {
                if let preference {
                    modelContext.delete(preference)
                    try modelContext.save()
                }
                return
            }

            let data = try JSONEncoder().encode(selectedCalendarIDs.sorted())
            let value = String(decoding: data, as: UTF8.self)

            if let preference {
                preference.value = value
            } else {
                modelContext.insert(
                    AppPreferenceModel(
                        key: Self.preferenceKey,
                        value: value
                    )
                )
            }
            try modelContext.save()
        } catch {
            throw SystemCalendarSelectionStoreError.persistenceFailed
        }
    }

    private func preferenceModel() throws -> AppPreferenceModel? {
        try modelContext
            .fetch(FetchDescriptor<AppPreferenceModel>())
            .first { $0.key == Self.preferenceKey }
    }
}

@MainActor
final class EventKitSystemCalendarService: SystemCalendarServiceProtocol {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func changes() -> AsyncStream<SystemCalendarChange> {
        let eventStore = self.eventStore

        return AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: eventStore,
                queue: .main
            ) { _ in
                continuation.yield(.storeChanged)
            }
            let observerBox = SystemCalendarChangeObserver(token: observer)

            continuation.onTermination = { @Sendable _ in
                observerBox.cancel()
            }
        }
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

    func requestWriteAccess() async -> SystemCalendarAccess {
        guard access == .notDetermined else {
            return access
        }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            eventStore.requestWriteOnlyAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        if granted, access == .notDetermined {
            return .writeOnly
        }
        return access
    }

    func calendars() async throws -> [SystemCalendarDescriptor] {
        try ensureReadAccess()

        return eventStore
            .calendars(for: .event)
            .map(Self.makeDescriptor)
            .sorted {
                if $0.displaySourceTitle != $1.displaySourceTitle {
                    return $0.displaySourceTitle.localizedStandardCompare($1.displaySourceTitle) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func writableCalendars() async throws -> [SystemCalendarDescriptor] {
        try ensureWriteAccess()

        if access == .writeOnly {
            guard let calendar = eventStore.defaultCalendarForNewEvents else {
                throw SystemCalendarWriteError.noWritableCalendar
            }
            return [Self.makeDescriptor(from: calendar)]
        }

        return eventStore
            .calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(Self.makeDescriptor)
            .sorted {
                if $0.displaySourceTitle != $1.displaySourceTitle {
                    return $0.displaySourceTitle.localizedStandardCompare($1.displaySourceTitle) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func createEvent(_ draft: SystemCalendarEventDraft, calendarID: String) async throws {
        try ensureWriteAccess()

        let calendar: EKCalendar
        if access == .writeOnly {
            guard let defaultCalendar = eventStore.defaultCalendarForNewEvents,
                  defaultCalendar.calendarIdentifier == calendarID else {
                throw SystemCalendarWriteError.calendarNotFound
            }
            calendar = defaultCalendar
        } else {
            guard let writableCalendar = eventStore
                .calendars(for: .event)
                .first(where: { $0.calendarIdentifier == calendarID }) else {
                throw SystemCalendarWriteError.calendarNotFound
            }
            guard writableCalendar.allowsContentModifications else {
                throw SystemCalendarWriteError.calendarNotWritable
            }
            calendar = writableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.notes = draft.note

        if draft.isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = DayID.defaultTimeZone
            let start = calendar.startOfDay(for: draft.startDate)
            let end = calendar.startOfDay(for: draft.endDate)
            event.isAllDay = true
            event.startDate = start
            event.endDate = calendar.date(byAdding: .day, value: 1, to: end) ?? draft.endDate
        } else {
            event.isAllDay = false
            event.startDate = draft.startDate
            event.endDate = draft.endDate
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw SystemCalendarWriteError.saveFailed
        }
    }

    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>? = nil
    ) async throws -> [SystemCalendarEventSnapshot] {
        guard interval.start <= interval.end else {
            throw SystemCalendarServiceError.invalidDateRange
        }

        try ensureReadAccess()

        if let calendarIDs, calendarIDs.isEmpty {
            return []
        }

        let calendars = eventStore.calendars(for: .event).filter { calendar in
            guard let calendarIDs else {
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

    private func ensureReadAccess() throws {
        switch access {
        case .fullAccess:
            return
        case .restricted:
            throw SystemCalendarServiceError.accessRestricted
        case .unavailable, .notDetermined, .denied, .writeOnly:
            throw SystemCalendarServiceError.permissionDenied
        }
    }

    private func ensureWriteAccess() throws {
        switch access {
        case .fullAccess, .writeOnly:
            return
        case .restricted:
            throw SystemCalendarWriteError.accessRestricted
        case .unavailable:
            throw SystemCalendarWriteError.unavailable
        case .notDetermined, .denied:
            throw SystemCalendarWriteError.permissionDenied
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

    private static func makeDescriptor(from calendar: EKCalendar) -> SystemCalendarDescriptor {
        SystemCalendarDescriptor(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: calendar.source?.title
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

@MainActor
final class FixtureSystemCalendarService: SystemCalendarServiceProtocol {
    let access: SystemCalendarAccess = .fullAccess
    private let changeStream: AsyncStream<SystemCalendarChange>
    private let changeContinuation: AsyncStream<SystemCalendarChange>.Continuation
    private(set) var createdEvents: [SystemCalendarEventSnapshot] = []

    let fixtureCalendars: [SystemCalendarDescriptor] = [
        SystemCalendarDescriptor(
            identifier: "fixture-work",
            title: "工作",
            sourceTitle: "测试账号"
        ),
        SystemCalendarDescriptor(
            identifier: "fixture-personal",
            title: "个人",
            sourceTitle: "本机日历"
        )
    ]

    init() {
        let changeStream = AsyncStream<SystemCalendarChange>.makeStream()
        self.changeStream = changeStream.stream
        self.changeContinuation = changeStream.continuation
    }

    func requestReadAccess() async -> SystemCalendarAccess {
        access
    }

    func requestWriteAccess() async -> SystemCalendarAccess {
        access
    }

    func changes() -> AsyncStream<SystemCalendarChange> {
        changeStream
    }

    func calendars() async throws -> [SystemCalendarDescriptor] {
        fixtureCalendars
    }

    func writableCalendars() async throws -> [SystemCalendarDescriptor] {
        fixtureCalendars
    }

    func createEvent(_ draft: SystemCalendarEventDraft, calendarID: String) async throws {
        guard let calendar = fixtureCalendars.first(where: { $0.identifier == calendarID }) else {
            throw SystemCalendarWriteError.calendarNotFound
        }

        let index = createdEvents.count + 1
        let event = SystemCalendarEventSnapshot(
            externalIdentifier: "fixture-created-event-\(index)",
            calendarItemIdentifier: "fixture-created-item-\(index)",
            title: draft.title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            timeZoneIdentifier: DayID.defaultTimeZoneIdentifier,
            calendarIdentifier: calendar.identifier,
            calendarTitle: calendar.title,
            sourceTitle: calendar.sourceTitle,
            note: draft.note
        )
        createdEvents.append(event)
        changeContinuation.yield(.storeChanged)
    }

    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>?
    ) async throws -> [SystemCalendarEventSnapshot] {
        guard interval.start <= interval.end else {
            throw SystemCalendarServiceError.invalidDateRange
        }

        let day = DayID(interval.start)
        guard let dayDate = day.date else {
            return []
        }

        let events = [
            SystemCalendarEventSnapshot(
                externalIdentifier: "fixture-work-event",
                calendarItemIdentifier: "fixture-work-item",
                title: "项目评审",
                startDate: dayDate.addingTimeInterval(9 * 60 * 60),
                endDate: dayDate.addingTimeInterval(10 * 60 * 60),
                isAllDay: false,
                timeZoneIdentifier: DayID.defaultTimeZoneIdentifier,
                calendarIdentifier: "fixture-work",
                calendarTitle: "工作",
                sourceTitle: "测试账号"
            ),
            SystemCalendarEventSnapshot(
                externalIdentifier: "fixture-personal-event",
                calendarItemIdentifier: "fixture-personal-item",
                title: "个人安排",
                startDate: dayDate.addingTimeInterval(19 * 60 * 60),
                endDate: dayDate.addingTimeInterval(20 * 60 * 60),
                isAllDay: false,
                timeZoneIdentifier: DayID.defaultTimeZoneIdentifier,
                calendarIdentifier: "fixture-personal",
                calendarTitle: "个人",
                sourceTitle: "本机日历"
            )
        ]

        let allEvents = events + createdEvents.filter {
            $0.startDate < interval.end && $0.endDate > interval.start
        }
        guard let calendarIDs else {
            return allEvents
        }
        return allEvents.filter { calendarIDs.contains($0.calendarIdentifier) }
    }
}
