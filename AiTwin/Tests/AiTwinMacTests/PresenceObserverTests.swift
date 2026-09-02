import AppKit
import Testing
@testable import AiTwinMac

/// Leaving the Mac and coming back.
///
/// Both notification centres are injected, so these post to throwaway local
/// ones. Posting to the real `DistributedNotificationCenter` is a system-wide
/// broadcast to every running application and must never happen from a test.
@Suite("Presence observer", .serialized)
@MainActor
struct PresenceObserverTests {

    /// An observer wired to two private centres, plus the counters.
    private final class Rig {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let observer: MacPresenceObserver
        var aways = 0
        var backs = 0

        init() {
            observer = MacPresenceObserver(workspaceCenter: workspace, distributedCenter: distributed)
            observer.onAway = { [unowned self] in self.aways += 1 }
            observer.onBack = { [unowned self] in self.backs += 1 }
            observer.start()
        }

        func post(_ name: Notification.Name, distributed isDistributed: Bool = false) {
            (isDistributed ? distributed : workspace).post(name: name, object: nil)
        }
    }

    @Test("a burst of notifications counts as one leaving and one returning")
    func burstsCollapse() {
        let rig = Rig()
        // Closing the lid on a Mac with a password set fires all three.
        rig.post(NSWorkspace.willSleepNotification)
        rig.post(.screenIsLocked, distributed: true)
        rig.post(NSWorkspace.screensDidSleepNotification)
        #expect(rig.aways == 1)
        #expect(rig.backs == 0)

        rig.post(NSWorkspace.didWakeNotification)
        rig.post(NSWorkspace.screensDidWakeNotification)
        rig.post(.screenIsUnlocked, distributed: true)
        #expect(rig.aways == 1)
        #expect(rig.backs == 1)
    }

    @Test("waking a still-locked Mac is not coming back")
    func wakingLockedIsNotAReturn() {
        let rig = Rig()
        rig.post(NSWorkspace.willSleepNotification)
        rig.post(.screenIsLocked, distributed: true)
        #expect(rig.aways == 1)

        // The lid is open and the display is on, but the login window is up.
        // This is the case a time-based coalescing window gets wrong: it would
        // have greeted the lock screen.
        rig.post(NSWorkspace.didWakeNotification)
        rig.post(NSWorkspace.screensDidWakeNotification)
        #expect(rig.backs == 0)

        rig.post(.screenIsUnlocked, distributed: true)
        #expect(rig.backs == 1)
    }

    @Test("sleep with no lock still works on public API alone")
    func sleepWithoutLock() {
        let rig = Rig()
        rig.post(NSWorkspace.willSleepNotification)
        #expect(rig.aways == 1)
        rig.post(NSWorkspace.didWakeNotification)
        #expect(rig.backs == 1)
    }

    @Test("the screensaver alone is enough to count as away")
    func screensaverOnly() {
        let rig = Rig()
        rig.post(.screensaverDidStart, distributed: true)
        #expect(rig.aways == 1)
        rig.post(.screensaverDidStop, distributed: true)
        #expect(rig.backs == 1)
    }

    @Test("fast user switching counts as away")
    func userSwitching() {
        let rig = Rig()
        rig.post(NSWorkspace.sessionDidResignActiveNotification)
        #expect(rig.aways == 1)
        rig.post(NSWorkspace.sessionDidBecomeActiveNotification)
        #expect(rig.backs == 1)
    }

    @Test("an unlock with no preceding lock reports nothing")
    func unmatchedUnlockIsIgnored() {
        let rig = Rig()
        rig.post(.screenIsUnlocked, distributed: true)
        rig.post(NSWorkspace.didWakeNotification)
        #expect(rig.aways == 0)
        #expect(rig.backs == 0)
    }

    @Test("locking twice without unlocking reports one leaving")
    func repeatedLock() {
        let rig = Rig()
        rig.post(.screenIsLocked, distributed: true)
        rig.post(.screenIsLocked, distributed: true)
        #expect(rig.aways == 1)
    }

    @Test("stop detaches from both centres")
    func stopDetaches() {
        let rig = Rig()
        rig.observer.stop()
        rig.post(.screenIsLocked, distributed: true)
        rig.post(NSWorkspace.willSleepNotification)
        #expect(rig.aways == 0)
    }

    @Test("start twice does not double-register")
    func startIsReentrant() {
        let rig = Rig()
        rig.observer.start()
        rig.observer.onAway = { rig.aways += 1 }
        rig.post(.screenIsLocked, distributed: true)
        #expect(rig.aways == 1)
    }
}
