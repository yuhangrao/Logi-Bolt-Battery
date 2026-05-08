import Foundation

public final class SnapshotStore {
    public static let shared = SnapshotStore()

    private let defaults: UserDefaults
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        guard let suite = UserDefaults(suiteName: AppGroup.id) else {
            fatalError("App Group \(AppGroup.id) is not configured for this target — check entitlements.")
        }
        self.defaults = suite
    }

    public func write(_ snapshot: BatterySnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: AppGroup.snapshotKey)
        } catch {
            NSLog("SnapshotStore.write encode failed: \(error)")
        }
    }

    public func read() -> BatterySnapshot? {
        guard let data = defaults.data(forKey: AppGroup.snapshotKey) else { return nil }
        return try? decoder.decode(BatterySnapshot.self, from: data)
    }
}
