import Foundation
import AiTwinCore

/// Mirrors settings and history into iCloud's key-value store.
///
/// `NSUbiquitousKeyValueStore` rather than CloudKit: this is a few kilobytes of
/// JSON, it needs no schema, no server-side records and no conflict UI, and it
/// works offline and reconciles later on its own. CloudKit would be a great deal
/// of machinery for two small blobs.
///
/// **Last write wins**, decided by a timestamp stored alongside the payload.
/// That is the right trade here: settings changed on two Macs in the same minute
/// is a rare and low-stakes conflict, and any merge UI would cost more attention
/// than the problem is worth.
///
/// Character packs are deliberately *not* synced — they are megabytes of images
/// and are usually chosen per machine.
///
/// **Needs verification on macOS:** iCloud key-value storage requires the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement, which needs a
/// paid Apple Developer account. Without it the store silently does nothing —
/// which is why every method here degrades to a no-op rather than failing.
public final class CloudSyncStore {

    private let store: NSUbiquitousKeyValueStore
    private let local: UserDefaults
    private var observer: NSObjectProtocol?

    private enum Key {
        static let settings = "cloud.settings.v1"
        static let settingsStamp = "cloud.settings.stamp.v1"
        static let activity = "cloud.activity.v1"
        static let activityStamp = "cloud.activity.stamp.v1"
    }

    /// Fired when iCloud brings newer data from another Mac.
    public var onRemoteChange: ((AiTwinSettings?, ActivityLog?) -> Void)?

    public init(store: NSUbiquitousKeyValueStore = .default, local: UserDefaults = .standard) {
        self.store = store
        self.local = local
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// True when iCloud is actually usable. False without the entitlement, or
    /// when the user is not signed in.
    public var isAvailable: Bool {
        // synchronize() returns false when the store is unavailable, which is
        // the only honest signal the API offers.
        store.synchronize()
    }

    public func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onRemoteChange?(self.remoteSettings(), self.remoteActivityLog())
        }
        store.synchronize()
    }

    // MARK: Writing

    public func push(settings: AiTwinSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.set(data, forKey: Key.settings)
        store.set(Date().timeIntervalSince1970, forKey: Key.settingsStamp)
        store.synchronize()
    }

    public func push(activityLog: ActivityLog) {
        guard let data = try? JSONEncoder().encode(activityLog) else { return }
        store.set(data, forKey: Key.activity)
        store.set(Date().timeIntervalSince1970, forKey: Key.activityStamp)
        store.synchronize()
    }

    // MARK: Reading

    public func remoteSettings() -> AiTwinSettings? {
        guard let data = store.data(forKey: Key.settings) else { return nil }
        return try? JSONDecoder().decode(AiTwinSettings.self, from: data)
    }

    public func remoteActivityLog() -> ActivityLog? {
        guard let data = store.data(forKey: Key.activity) else { return nil }
        return try? JSONDecoder().decode(ActivityLog.self, from: data)
    }

    /// Whether the copy in iCloud is newer than what this Mac last wrote.
    public func remoteSettingsAreNewer() -> Bool {
        isNewer(remote: Key.settingsStamp, localKey: "local.settings.stamp")
    }

    public func remoteActivityIsNewer() -> Bool {
        isNewer(remote: Key.activityStamp, localKey: "local.activity.stamp")
    }

    private func isNewer(remote remoteKey: String, localKey: String) -> Bool {
        let remote = store.double(forKey: remoteKey)
        let mine = local.double(forKey: localKey)
        return remote > mine
    }

    public func noteLocalWrite() {
        let now = Date().timeIntervalSince1970
        local.set(now, forKey: "local.settings.stamp")
        local.set(now, forKey: "local.activity.stamp")
    }
}
