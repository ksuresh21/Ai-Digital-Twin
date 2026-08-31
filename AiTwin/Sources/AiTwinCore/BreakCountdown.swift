import Foundation

/// The timed eye-break: a countdown during which the screen dims.
///
/// The whole point of the eye-break feature is that you *actually* look away,
/// and a message you can dismiss in half a second does not achieve that. This
/// runs a real countdown so there is something to wait out.
///
/// Deadline-based like the reminder timers, so it stays correct if the app is
/// briefly starved of CPU, and driven by an explicit clock so it is testable.
public struct BreakCountdown: Equatable, Sendable {
    public let duration: TimeInterval
    public let startedAt: Date

    public init(duration: TimeInterval, startedAt: Date) {
        self.duration = max(0, duration)
        self.startedAt = startedAt
    }

    public var endsAt: Date { startedAt.addingTimeInterval(duration) }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    public func isFinished(at now: Date) -> Bool {
        now >= endsAt
    }

    /// 0...1, for a progress ring.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (duration - remaining(at: now)) / duration))
    }

    /// Whole seconds left, for display. Rounds up so a countdown starting at 20
    /// shows "20" rather than blinking straight to "19".
    public func secondsRemaining(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    /// The choices offered in Settings. A minute is the default: long enough
    /// that your eyes actually refocus on something distant, short enough that
    /// it does not feel like being sent out of the room.
    public static let durationChoices: [TimeInterval] = [20, 30, 60, 120]

    public static func durationName(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) seconds" }
        let minutes = Int(seconds / 60)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
