import Foundation

/// A Pomodoro-style focus session.
///
/// While one runs, **every reminder is suppressed** — water included. A
/// hydration nudge in the middle of deep work is precisely the interruption the
/// session exists to prevent. Suppressed reminders are not discarded: they are
/// held and delivered in the break, which is when you can act on them anyway.
public struct FocusSession: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        /// Working. The character sits still and reads.
        case working
        /// Short rest between sessions.
        case shortBreak
        /// Longer rest after a set of sessions.
        case longBreak

        public var isBreak: Bool { self != .working }

        public var displayName: String {
            switch self {
            case .working:    return "Focus"
            case .shortBreak: return "Break"
            case .longBreak:  return "Long break"
            }
        }
    }

    public let phase: Phase
    public let duration: TimeInterval
    public let startedAt: Date
    /// How many working sessions have completed in this run, including this one
    /// once it finishes. Drives when a long break is due.
    public let completedSessions: Int

    public init(phase: Phase, duration: TimeInterval, startedAt: Date, completedSessions: Int) {
        self.phase = phase
        self.duration = max(0, duration)
        self.startedAt = startedAt
        self.completedSessions = completedSessions
    }

    public var endsAt: Date { startedAt.addingTimeInterval(duration) }

    /// Whether arriving in this phase means a previous one just *ended*.
    ///
    /// Every phase change is an ending except the first, which is a beginning
    /// with nothing behind it to announce. The two are told apart without a
    /// flag: the opening phase is always `.working` with no sessions completed
    /// yet, and a `.working` phase reached any other way follows a break.
    public var endsAPreviousPhase: Bool {
        phase.isBreak || completedSessions > 0
    }

    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
    public func isFinished(at now: Date) -> Bool { now >= endsAt }

    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (duration - remaining(at: now)) / duration))
    }

    /// "24:31" — the countdown shown above her head.
    public func clockText(at now: Date) -> String {
        let total = Int(remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Runs the session cycle: work, break, work, break, long break.
///
/// Pure and clock-driven like everything else in Core, so a full four-session
/// set can be simulated in a test without waiting two hours.
public final class FocusController {
    public private(set) var session: FocusSession?
    /// Working sessions finished since the cycle began.
    public private(set) var completedSessions: Int = 0

    private let clock: Clock
    private var settings: AiTwinSettings

    public var onPhaseChange: ((FocusSession?) -> Void)?
    /// Fired when a working session completes, for the activity log.
    public var onSessionCompleted: ((Double) -> Void)?

    public init(settings: AiTwinSettings, clock: Clock) {
        self.settings = settings
        self.clock = clock
    }

    public var isActive: Bool { session != nil }
    /// True only while actually working — breaks do not suppress reminders.
    public var isWorking: Bool { session?.phase == .working }

    public func apply(_ newSettings: AiTwinSettings) {
        settings = newSettings
    }

    public func start() {
        completedSessions = 0
        begin(.working)
    }

    public func stop() {
        session = nil
        completedSessions = 0
        onPhaseChange?(nil)
    }

    /// Ends the current phase early and moves to the next.
    public func skip() {
        guard session != nil else { return }
        advance(at: clock.now)
    }

    /// Call about once a second while a session is active.
    public func tick() {
        guard let session else { return }
        let now = clock.now
        guard session.isFinished(at: now) else { return }
        advance(at: now)
    }

    private func advance(at now: Date) {
        guard let finished = session else { return }
        if finished.phase == .working {
            completedSessions += 1
            onSessionCompleted?(finished.duration / 60)
            // A long break after every Nth working session.
            let isLongDue = settings.sessionsBeforeLongBreak > 0
                && completedSessions % settings.sessionsBeforeLongBreak == 0
            begin(isLongDue ? .longBreak : .shortBreak)
        } else {
            begin(.working)
        }
    }

    private func begin(_ phase: FocusSession.Phase) {
        let duration: TimeInterval
        switch phase {
        case .working:    duration = settings.focusSessionLength
        case .shortBreak: duration = settings.focusBreakLength
        case .longBreak:  duration = settings.focusLongBreakLength
        }
        session = FocusSession(
            phase: phase,
            duration: duration,
            startedAt: clock.now,
            completedSessions: completedSessions
        )
        onPhaseChange?(session)
    }

    /// Session-length choices offered in Settings.
    public static let lengthChoices: [TimeInterval] = [25 * 60, 45 * 60, 50 * 60]
    public static let breakChoices: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60]

    public static func lengthName(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60)) minutes"
    }
}
