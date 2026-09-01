import Foundation

/// Watches how the day is going and decides when the character should show
/// concern or look sleepy.
///
/// Both moods exist to be *noticed*, which means they must be rare. Concern
/// shown too often is nagging, and a companion that looks tired every evening is
/// wallpaper. So each has a hard cooldown and a set of conditions that all have
/// to hold — the same discipline as `ChatterScheduler`.
public struct MoodMonitor: Equatable, Sendable {

    /// What the monitor thinks she should express, if anything.
    public enum Mood: String, Equatable, Sendable {
        /// You have been at it a long time, or waved several reminders away.
        case concerned
        /// It is late, or the session has run very long.
        case sleepy

        public var clipName: String {
            switch self {
            case .concerned: return ClipName.concerned
            case .sleepy:    return ClipName.yawn
            }
        }
    }

    // MARK: Thresholds

    /// The numbers behind each mood, all exposed in Settings.
    public struct Thresholds: Codable, Equatable, Sendable {
        /// Reminders brushed aside in a row before she checks on you.
        public var skipsBeforeConcern: Int
        /// Unbroken screen time before she checks on you.
        public var workBeforeConcern: TimeInterval
        /// Minutes since midnight after which she starts winding down.
        public var nightStartMinutes: Int
        /// How often she reappears sleepy once it is night.
        public var sleepyRepeat: TimeInterval
        /// Unbroken screen time that makes her sleepy whatever the clock says.
        public var workBeforeSleepy: TimeInterval

        public init(
            skipsBeforeConcern: Int = 3,
            workBeforeConcern: TimeInterval = 3 * 60 * 60,
            nightStartMinutes: Int = 22 * 60,
            sleepyRepeat: TimeInterval = 30 * 60,
            workBeforeSleepy: TimeInterval = 5 * 60 * 60
        ) {
            self.skipsBeforeConcern = max(1, skipsBeforeConcern)
            self.workBeforeConcern = max(60, workBeforeConcern)
            self.nightStartMinutes = min(1439, max(0, nightStartMinutes))
            self.sleepyRepeat = max(60, sleepyRepeat)
            self.workBeforeSleepy = max(60, workBeforeSleepy)
        }

        public static let `default` = Thresholds()

        public static let concernHourChoices: [TimeInterval] = [1 * 3600, 2 * 3600, 3 * 3600, 4 * 3600]
        public static let nightStartChoices: [Int] = [21 * 60, 21 * 60 + 30, 22 * 60, 22 * 60 + 30, 23 * 60]
        public static let repeatChoices: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60]
    }

    /// Minimum gap between two *concern* moods. Sleepiness has its own,
    /// shorter repeat, because at night the whole point is a gentle nag.
    public static let concernCooldown: TimeInterval = 2 * 60 * 60
    /// Do not comment on how hard you are working if you are not at the Mac.
    public static let maximumIdleSeconds: TimeInterval = 3 * 60

    // MARK: State

    /// Reminders snoozed or ignored since the last one was accepted.
    public private(set) var consecutiveSkips = 0
    /// When the current unbroken stretch of work began.
    public private(set) var workStartedAt: Date?
    public private(set) var lastConcernAt: Date?
    public private(set) var lastSleepyAt: Date?
    public var thresholds: Thresholds

    public init(
        consecutiveSkips: Int = 0,
        workStartedAt: Date? = nil,
        lastConcernAt: Date? = nil,
        lastSleepyAt: Date? = nil,
        thresholds: Thresholds = .default
    ) {
        self.consecutiveSkips = consecutiveSkips
        self.workStartedAt = workStartedAt
        self.lastConcernAt = lastConcernAt
        self.lastSleepyAt = lastSleepyAt
        self.thresholds = thresholds
    }

    // MARK: Recording

    /// A reminder was accepted: the slate is clean and the stretch restarts.
    public mutating func noteAccepted(at now: Date) {
        consecutiveSkips = 0
        workStartedAt = now
    }

    /// A reminder was snoozed or timed out.
    public mutating func noteSkipped() {
        consecutiveSkips += 1
    }

    /// Called when the user is present. Starts the clock on a stretch of work.
    public mutating func noteActive(at now: Date) {
        if workStartedAt == nil { workStartedAt = now }
    }

    /// The user stepped away long enough that the stretch no longer counts.
    public mutating func noteAway() {
        workStartedAt = nil
    }

    public mutating func noteMoodShown(_ mood: Mood, at now: Date) {
        switch mood {
        case .concerned:
            lastConcernAt = now
            // She asks once and lets it go, rather than repeating every time
            // another reminder is waved away.
            consecutiveSkips = 0
        case .sleepy:
            lastSleepyAt = now
        }
    }

    // MARK: Deciding

    public func continuousWork(at now: Date) -> TimeInterval {
        guard let workStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(workStartedAt))
    }

    /// Everything that can veto a mood.
    public struct Conditions: Equatable, Sendable {
        public var isPaused: Bool
        public var inQuietHours: Bool
        public var isFocusing: Bool
        public var characterIsBusy: Bool
        public var idleSeconds: TimeInterval

        public init(
            isPaused: Bool = false,
            inQuietHours: Bool = false,
            isFocusing: Bool = false,
            characterIsBusy: Bool = false,
            idleSeconds: TimeInterval = 0
        ) {
            self.isPaused = isPaused
            self.inQuietHours = inQuietHours
            self.isFocusing = isFocusing
            self.characterIsBusy = characterIsBusy
            self.idleSeconds = idleSeconds
        }
    }

    /// The mood to show now, or nil.
    ///
    /// Sleepiness is checked first: at one in the morning after a six-hour
    /// session, "you should sleep" is the more useful of the two.
    public func mood(at now: Date, conditions: Conditions, calendar: Calendar = .current) -> Mood? {
        guard !conditions.isPaused,
              !conditions.inQuietHours,
              !conditions.isFocusing,
              !conditions.characterIsBusy,
              conditions.idleSeconds < Self.maximumIdleSeconds
        else { return nil }

        let worked = continuousWork(at: now)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Night runs from the configured start until 5am, so it spans midnight.
        let isNight = minuteOfDay >= thresholds.nightStartMinutes || minuteOfDay < 5 * 60

        if isNight || worked >= thresholds.workBeforeSleepy {
            let due = lastSleepyAt.map { now.timeIntervalSince($0) >= thresholds.sleepyRepeat } ?? true
            if due { return .sleepy }
            // Already nudged recently about sleep; do not swap to concern
            // instead, or the night would fill with alternating moods.
            return nil
        }

        if let lastConcernAt, now.timeIntervalSince(lastConcernAt) < Self.concernCooldown { return nil }
        if consecutiveSkips >= thresholds.skipsBeforeConcern { return .concerned }
        if worked >= thresholds.workBeforeConcern { return .concerned }
        return nil
    }
}
