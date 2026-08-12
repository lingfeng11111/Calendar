import Foundation
import SwiftData

@MainActor
protocol NotificationPreferencesStoreProtocol {
    func load() throws -> CalendarNotificationPreferences?
    func save(_ preferences: CalendarNotificationPreferences?) throws
}

enum NotificationPreferencesStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidStoredValue
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            "通知规则设置无法读取"
        case .persistenceFailed:
            "通知规则设置无法保存"
        }
    }
}

@MainActor
final class SwiftDataNotificationPreferencesStore: NotificationPreferencesStoreProtocol {
    static let preferenceKey = "notifications.preferences.v1"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() throws -> CalendarNotificationPreferences? {
        do {
            guard let preference = try preferenceModel() else {
                return nil
            }
            guard let data = preference.value.data(using: .utf8) else {
                throw NotificationPreferencesStoreError.invalidStoredValue
            }
            do {
                return try JSONDecoder().decode(CalendarNotificationPreferences.self, from: data)
            } catch {
                throw NotificationPreferencesStoreError.invalidStoredValue
            }
        } catch let error as NotificationPreferencesStoreError {
            throw error
        } catch {
            throw NotificationPreferencesStoreError.persistenceFailed
        }
    }

    func save(_ preferences: CalendarNotificationPreferences?) throws {
        do {
            let preference = try preferenceModel()
            guard let preferences else {
                if let preference {
                    modelContext.delete(preference)
                    try modelContext.save()
                }
                return
            }

            let data = try JSONEncoder().encode(preferences)
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
            throw NotificationPreferencesStoreError.persistenceFailed
        }
    }

    private func preferenceModel() throws -> AppPreferenceModel? {
        try modelContext
            .fetch(FetchDescriptor<AppPreferenceModel>())
            .first { $0.key == Self.preferenceKey }
    }
}
