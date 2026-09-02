import AppKit
import AiTwinPlatform

/// Watches the system for the user leaving the Mac and coming back.
///
/// "Leaving" means the screen locked, the screensaver started, the machine or
/// its displays went to sleep, or another user switched in. "Coming back" is
/// the inverse -- but only once *every* one of those has cleared, which is the
/// whole reason this is one object rather than two.
///
/// ## Why latches and not a time window
///
/// Closing the lid on a Mac with a password set fires `willSleep` **and**
/// `screenIsLocked`. Opening it fires `didWake` and `screensDidWake` while the
/// login window is still up. A naive "coalesce anything within five seconds"
/// scheme greets the lock screen. Instead each source owns a latch, and the
/// callbacks fire on the edges of their OR: opening the lid clears
/// `machineAsleep` but leaves `screenLocked` set, so nothing is reported until
/// `screenIsUnlocked` actually arrives. Bursts collapse for free, because the
/// second notification of a burst finds the OR already true.
///
/// ## Private API, and what happens when it fails
///
/// `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` are **not
/// documented API**. No header declares them. They have worked since roughly
/// 10.9 and a great deal of shipping software depends on them, but Apple owes
/// us nothing here, and they are not usable from a sandboxed (App Store) build
/// -- see Docs/PACKAGING.md.
///
/// The latch design degrades rather than breaks: if the lock notifications stop
/// arriving, sleep and fast-user-switching still drive away/back through public
/// API. The one bad case is a *dropped* `screenIsUnlocked`, which would leave
/// `screenLocked` latched and the character away until the app restarts. If
/// that is ever seen in practice, reconcile against
/// `CGSessionCopyCurrentDictionary()` while away -- but only then, and never as
/// the primary signal.
public final class MacPresenceObserver: PresenceObserving {

    public var onAway: (() -> Void)?
    public var onBack: (() -> Void)?

    /// Screen lock and screensaver. Undocumented names -- see the note above.
    private var screenLocked = false
    /// The machine or its displays are asleep.
    private var machineAsleep = false
    /// Another user is in front. Fast user switching.
    private var sessionInactive = false

    /// What we last told the app. The callbacks fire on changes to this.
    private var isAway = false

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// - Parameters:
    ///   - workspaceCenter: sleep, wake and session switching.
    ///   - distributedCenter: lock, unlock and the screensaver. Typed as the
    ///     base `NotificationCenter` rather than `DistributedNotificationCenter`
    ///     so tests can inject a local centre -- posting to the real
    ///     distributed centre is a system-wide broadcast to every running app.
    public init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
    }

    deinit { stop() }

    public func start() {
        stop()
        observe(distributedCenter, .screenIsLocked)      { $0.screenLocked = true }
        observe(distributedCenter, .screenIsUnlocked)    { $0.screenLocked = false }
        observe(distributedCenter, .screensaverDidStart) { $0.screenLocked = true }
        observe(distributedCenter, .screensaverDidStop)  { $0.screenLocked = false }

        observe(workspaceCenter, NSWorkspace.willSleepNotification)        { $0.machineAsleep = true }
        observe(workspaceCenter, NSWorkspace.didWakeNotification)          { $0.machineAsleep = false }
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification)  { $0.machineAsleep = true }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification)   { $0.machineAsleep = false }

        observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
    }

    public func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        apply: @escaping (MacPresenceObserver) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            apply(self)
            self.publish()
        }
        tokens.append((center, token))
    }

    /// Reports a change only when the combined picture flips.
    private func publish() {
        let away = screenLocked || machineAsleep || sessionInactive
        guard away != isAway else { return }
        isAway = away
        away ? onAway?() : onBack?()
    }
}

extension Notification.Name {
    /// Undocumented. See the note on `MacPresenceObserver`.
    static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    /// macOS 14 merged the screensaver and the lock screen, so these two are
    /// the least reliable of the set. They are additional inputs, never
    /// load-bearing: everything still works if they never arrive.
    static let screensaverDidStart = Notification.Name("com.apple.screensaver.didstart")
    static let screensaverDidStop = Notification.Name("com.apple.screensaver.didstop")
}
