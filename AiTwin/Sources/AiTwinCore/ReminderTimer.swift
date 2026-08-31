import Foundation

/// A single countdown, expressed as an absolute deadline.
///
/// Deadline-based rather than tick-counting on purpose. A timer that counts
/// 2400 one-second ticks toward a 40-minute eye-break is destroyed by a lid
/// close: the ticks stop, and the reminder arrives 40 minutes of *awake* time
/// later. Comparing `Date()` against a stored deadline survives sleep, wake,
/// clock changes and a busy main thread, and it is trivially testable with a
/// fake clock.
public final class ReminderTimer {
    public let kind: ReminderKind
    public private(set) var interval: TimeInterval
    /// When this timer next fires. Nil when stopped or paused.
    public private(set) var deadline: Date?
    public private(set) var isPaused: Bool = false

    /// Time left at the moment of pausing, so resuming does not lose progress.
    private var pausedRemaining: TimeInterval?

    public init(kind: ReminderKind, interval: TimeInterval) {
        self.kind = kind
        self.interval = interval
    }

    public var isRunning: Bool { deadline != nil }
    public var isActive: Bool { deadline != nil || pausedRemaining != nil }

    /// Starts (or restarts) a full interval from `now`.
    public func start(at now: Date) {
        isPaused = false
        pausedRemaining = nil
        deadline = now.addingTimeInterval(interval)
    }

    public func stop() {
        deadline = nil
        pausedRemaining = nil
        isPaused = false
    }

    /// Freezes the countdown, keeping the time remaining.
    ///
    /// Used for quiet hours, a global pause, and stepping away from the
    /// keyboard -- in all three cases the user has not "used" that time, so it
    /// should not count toward the next reminder.
    public func pause(at now: Date) {
        guard !isPaused else { return }
        if let deadline {
            pausedRemaining = max(0, deadline.timeIntervalSince(now))
        }
        deadline = nil
        isPaused = true
    }

    public func resume(at now: Date) {
        guard isPaused else { return }
        isPaused = false
        if let remaining = pausedRemaining {
            deadline = now.addingTimeInterval(remaining)
            pausedRemaining = nil
        }
    }

    /// Pushes the deadline out by `duration` from now.
    public func snooze(by duration: TimeInterval, at now: Date) {
        isPaused = false
        pausedRemaining = nil
        deadline = now.addingTimeInterval(duration)
    }

    public func hasFired(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    public func remaining(at now: Date) -> TimeInterval? {
        if let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return pausedRemaining
    }

    /// Changes the interval. An active timer is restarted so the new interval
    /// takes effect immediately rather than after one more old-length cycle --
    /// otherwise switching to Test Mode appears to do nothing for 40 minutes.
    public func setInterval(_ newInterval: TimeInterval, at now: Date) {
        let wasPaused = isPaused
        let wasActive = isActive
        interval = newInterval
        guard wasActive else { return }
        start(at: now)
        if wasPaused { pause(at: now) }
    }
}
