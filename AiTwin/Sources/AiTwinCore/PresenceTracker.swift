import Foundation

/// Decides whether a spell away from the Mac was long enough to matter.
///
/// The character disappears the instant the screen locks, whatever the
/// duration — that part is not negotiable and does not live here. This only
/// decides whether *coming back* is an event: whether the reminder cycles
/// restart from scratch, and whether she says hello.
///
/// Sixty seconds spent fetching a coffee is not a return. Resetting a
/// twenty-minute cycle because someone locked their screen on the way past the
/// kettle would be worse than not resetting at all, and a greeting every time
/// is exactly the nagging the rest of this app is written to avoid.
///
/// A value type with an injected `now`, like `MoodMonitor`, so the whole rule
/// is provable in a unit test rather than buried in the coordinator.
public struct PresenceTracker: Equatable, Sendable {

    /// Below this, being away is a blink: nothing resets and nothing is said.
    public static let minimumAway: TimeInterval = 60

    /// What coming back should mean.
    public enum Return: Equatable, Sendable {
        /// Away, but only briefly. Resume the timers; change nothing else.
        case brief(TimeInterval)
        /// A real absence. Restart the cycles and greet.
        case significant(TimeInterval)
        /// A "back" with no matching "away" — ignore it entirely.
        case spurious
    }

    /// When the current absence began, or nil if the user is here.
    public private(set) var awaySince: Date?
    /// How long an absence has to run before returning from it counts.
    public let minimumAway: TimeInterval

    public var isAway: Bool { awaySince != nil }

    public init(minimumAway: TimeInterval = PresenceTracker.minimumAway) {
        self.minimumAway = max(0, minimumAway)
    }

    /// The screen locked, the Mac slept, or the screensaver started.
    ///
    /// - Returns: false if we already believed the user was away, so a burst of
    ///   system notifications — a lid close fires several — acts exactly once.
    @discardableResult
    public mutating func noteAway(at now: Date) -> Bool {
        guard awaySince == nil else { return false }
        awaySince = now
        return true
    }

    /// The user unlocked, or the Mac woke.
    public mutating func noteBack(at now: Date) -> Return {
        guard let start = awaySince else { return .spurious }
        awaySince = nil
        // A clock that jumped backwards must not turn into a negative absence.
        let elapsed = max(0, now.timeIntervalSince(start))
        return elapsed >= minimumAway ? .significant(elapsed) : .brief(elapsed)
    }
}
