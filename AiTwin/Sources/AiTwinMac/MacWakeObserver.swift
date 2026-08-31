import AppKit
import AiTwinPlatform

/// Notices when the Mac wakes or the screen is unlocked, so the character can
/// say hello again.
///
/// Both notifications are observed because they are genuinely different events:
/// closing and opening the lid wakes the machine, while walking away and coming
/// back only ends the screen-lock session. A companion should greet you in both
/// cases. They are coalesced so a wake that also unlocks produces one greeting,
/// not two.
public final class MacWakeObserver: WakeObserving {

    public var onWake: (() -> Void)?
    /// Ignore a second wake signal within this window.
    private let coalescingInterval: TimeInterval = 5

    private var tokens: [NSObjectProtocol] = []
    private var lastFired: Date?

    public init() {}

    public func start() {
        stop()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        tokens = names.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.fire()
            }
        }
    }

    public func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        tokens.forEach { workspaceCenter.removeObserver($0) }
        tokens.removeAll()
    }

    deinit { stop() }

    private func fire() {
        let now = Date()
        if let lastFired, now.timeIntervalSince(lastFired) < coalescingInterval { return }
        lastFired = now
        onWake?()
    }
}
