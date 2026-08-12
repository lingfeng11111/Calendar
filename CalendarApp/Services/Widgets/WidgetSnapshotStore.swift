import Foundation

enum CalendarWidgetSnapshotStoreError: Error, Equatable, LocalizedError, Sendable {
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Widget 快照无法保存"
        case .decodingFailed:
            "Widget 快照无法读取"
        }
    }
}

struct CalendarWidgetSnapshotStore {
    static let snapshotKey = "calendar.widget.snapshot.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: CalendarWidgetSnapshot.appGroupIdentifier)
            ?? .standard
    }

    func load() throws -> CalendarWidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }

        do {
            let snapshot = try JSONDecoder().decode(CalendarWidgetSnapshot.self, from: data)
            guard snapshot.schemaVersion == CalendarWidgetSnapshot.schemaVersion else {
                throw CalendarWidgetSnapshotStoreError.decodingFailed
            }
            return snapshot
        } catch let error as CalendarWidgetSnapshotStoreError {
            throw error
        } catch {
            throw CalendarWidgetSnapshotStoreError.decodingFailed
        }
    }

    func save(_ snapshot: CalendarWidgetSnapshot) throws {
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
        } catch {
            throw CalendarWidgetSnapshotStoreError.encodingFailed
        }
    }

    func remove() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
