import Foundation

/// Something the engine wants the rest of the app to react to.
public enum ReminderEvent: Equatable, Sendable {
    /// A reminder is due. The message is already chosen so the UI has no policy.
    case reminderDue(ReminderKind, message: String)
    /// The user acknowledged. The next cycle has already been scheduled.
    case reminderAcknowledged(ReminderKind)
    case reminderSnoozed(ReminderKind, until: Date)
    /// Nobody responded within `reminderTimeout`; treated as a snooze so the
    /// character does not stand there indefinitely on an unattended Mac.
    case reminderTimedOut(ReminderKind)
    /// The screen locked while this reminder was on screen, so it was taken
    /// down rather than left standing against a display nobody can see.
    case reminderWithdrawn(ReminderKind)
    case waterLogged(glasses: Int, goal: Int, goalJustReached: Bool)
}

/// Why the engine is currently not counting down. Surfaced in the menu bar so
/// "why has it gone quiet?" always has a visible answer.
public enum EngineHoldReason: String, Equatable, Sendable, CaseIterable {
    /// The screen is locked, or the Mac is asleep.
    ///
    /// Listed first because it outranks everything else, and because it is the
    /// only reason that states a fact about the world rather than a preference.
    /// It is deliberately *not* folded into `userIdle`: that one is gated on
    /// `settings.pauseWhenIdle`, which the user can switch off, whereas a
    /// locked screen must never accumulate screen time whatever the settings say.
    case away
    case paused
    case quietHours
    case userIdle
    /// A focus session is running. Reminders are held, not dropped.
    case focusing

    public var displayName: String {
        switch self {
        case .away:       return "Away — timers on hold"
        case .paused:     return "Paused"
        case .quietHours: return "Quiet hours — staying quiet"
        case .userIdle:   return "You're away — timers on hold"
        case .focusing:   return "Focusing — reminders held"
        }
    }
}

/// Owns the reminder timers and decides when the character should appear.
///
/// Deliberately has no timer of its own: the app calls `tick(idleSeconds:)` from
/// one shared repeating timer. That keeps every scheduling decision synchronous
/// and testable -- a whole day of reminders can be simulated in a few
/// microseconds against a `FakeClock`.
public final class ReminderEngine {

    public private(set) var settings: AiTwinSettings
    public private(set) var configuration: AiTwinConfiguration
    public private(set) var waterLog: WaterLog
    /// The reminder currently on screen, if any.
    public private(set) var activeReminder: ReminderKind?
    public private(set) var holdReason: EngineHoldReason?
    /// Set by the app while a focus session is working. Suppresses everything.
    public var isFocusing: Bool = false
    /// True between `beginAway()` and `endAway(resetCycles:)` — the screen is
    /// locked, or the Mac is asleep.
    public private(set) var isAway = false
    /// Written to on every acknowledged, snoozed or ignored reminder.
    public private(set) var activityLog: ActivityLog

    public var onEvent: ((ReminderEvent) -> Void)?

    private let clock: Clock
    private let calendar: Calendar
    private let catalog: MessageCatalog
    private let waterLogStore: WaterLogStoring?
    private let activityLogStore: ActivityLogStoring?
    private var timers: [ReminderKind: ReminderTimer] = [:]
    private var activeSince: Date?
    private var isStarted = false

    public init(
        settings: AiTwinSettings,
        configuration: AiTwinConfiguration = .production,
        clock: Clock,
        catalog: MessageCatalog = MessageCatalog(),
        calendar: Calendar = .current,
        waterLogStore: WaterLogStoring? = nil,
        activityLogStore: ActivityLogStoring? = nil
    ) {
        self.settings = settings
        self.configuration = configuration
        self.clock = clock
        self.catalog = catalog
        self.calendar = calendar
        self.waterLogStore = waterLogStore
        self.activityLogStore = activityLogStore
        self.activityLog = activityLogStore?.load() ?? ActivityLog()
        self.waterLog = waterLogStore?.load() ?? WaterLog.empty(at: clock.now, calendar: calendar)

        for kind in ReminderKind.allCases {
            timers[kind] = ReminderTimer(kind: kind, interval: settings.interval(for: kind))
        }
    }

    // MARK: Lifecycle

    /// Schedules the first cycle of every enabled reminder.
    public func start() {
        isStarted = true
        let now = clock.now
        waterLog = waterLog.rolledOver(to: now, calendar: calendar)
        for kind in ReminderKind.allCases {
            guard let timer = timers[kind] else { continue }
            if settings.isEnabled(kind) {
                timer.start(at: now)
            } else {
                timer.stop()
            }
        }
        applyHold(at: now, idleSeconds: 0)
    }

    public func stop() {
        isStarted = false
        isAway = false
        timers.values.forEach { $0.stop() }
        activeReminder = nil
        activeSince = nil
    }

    // MARK: Away

    /// The screen locked, the Mac slept, or the screensaver started.
    ///
    /// Everything stops: no countdown advances while the user is not there, and
    /// anything already on screen is withdrawn rather than left to time out
    /// against a display nobody can see.
    ///
    /// Idempotent, because a single lid close fires several system
    /// notifications and they must add up to one effect.
    public func beginAway() {
        guard !isAway else { return }
        isAway = true
        let now = clock.now
        if let active = activeReminder { withdraw(active, at: now) }
        applyHold(at: now, idleSeconds: 0)
    }

    /// The user unlocked, or the Mac woke.
    ///
    /// - Parameter resetCycles: start every enabled reminder's cycle from
    ///   scratch. True for a real absence — time spent away from the Mac is not
    ///   screen time, so a twenty-minute water cycle that was fifteen minutes in
    ///   when the screen locked owes a full twenty minutes, not five. False for
    ///   the minute it takes to fetch a coffee, where throwing away the banked
    ///   progress would be absurd.
    public func endAway(resetCycles: Bool) {
        guard isAway else { return }
        isAway = false
        let now = clock.now
        // Recompute the hold *first*, so the restarts below see the world as it
        // is now rather than through the stale `.away`.
        applyHold(at: now, idleSeconds: 0)
        guard resetCycles else { return }
        for kind in ReminderKind.allCases {
            restartCycle(for: kind, at: now)
        }
    }

    /// Takes a reminder off the screen because the Mac locked.
    ///
    /// Recorded as a skip, so the history stays honest about a reminder that
    /// was shown and not acted on. The cycle restarts from scratch rather than
    /// snoozing, so she asks again a full interval after the user comes back
    /// instead of the moment they sit down.
    private func withdraw(_ kind: ReminderKind, at now: Date) {
        activeReminder = nil
        activeSince = nil
        record(.reminderIgnored(kind), at: now)
        restartCycle(for: kind, at: now)
        onEvent?(.reminderWithdrawn(kind))
    }

    // MARK: The tick

    /// Advances the engine. Call roughly once per `configuration.tickInterval`.
    ///
    /// - Parameter idleSeconds: seconds since the last keyboard or mouse event.
    ///   Supplied by the platform layer so Core stays free of system APIs.
    public func tick(idleSeconds: TimeInterval = 0) {
        guard isStarted else { return }
        let now = clock.now
        waterLog = waterLog.rolledOver(to: now, calendar: calendar)

        // A reminder already on screen blocks everything else: two characters
        // talking over each other is worse than a late reminder.
        if let active = activeReminder {
            if let since = activeSince,
               configuration.reminderTimeout > 0,
               now.timeIntervalSince(since) >= configuration.reminderTimeout {
                timeOut(active, at: now)
            }
            return
        }

        applyHold(at: now, idleSeconds: idleSeconds)
        guard holdReason == nil else { return }

        // Fixed order rather than "whichever fired first" so behaviour is
        // deterministic when both come due in the same tick.
        for kind in [ReminderKind.water, .eyeBreak, .stretch] {
            guard settings.isEnabled(kind), let timer = timers[kind], timer.hasFired(at: now) else { continue }
            present(kind, at: now)
            return
        }
    }

    /// Pauses or resumes timers according to away / pause / focus / quiet hours
    /// / idle state, in that order of precedence.
    private func applyHold(at now: Date, idleSeconds: TimeInterval) {
        let reason: EngineHoldReason?
        if isAway {
            // Outranks every other reason. A locked screen is not a preference.
            reason = .away
        } else if settings.remindersPaused {
            reason = .paused
        } else if isFocusing {
            // Held, not cancelled: the deadline is preserved, so a reminder due
            // mid-session arrives as soon as the break begins.
            reason = .focusing
        } else if settings.quietHours.contains(now, calendar: calendar) {
            reason = .quietHours
        } else if settings.pauseWhenIdle && idleSeconds >= settings.idleThreshold {
            reason = .userIdle
        } else {
            reason = nil
        }

        holdReason = reason
        for timer in timers.values {
            if reason == nil {
                timer.resume(at: now)
            } else {
                timer.pause(at: now)
            }
        }
    }

    // MARK: Presenting and responding

    private func present(_ kind: ReminderKind, at now: Date) {
        activeReminder = kind
        activeSince = now
        timers[kind]?.stop()
        onEvent?(.reminderDue(kind, message: catalog.nextMessage(for: kind, name: settings.userName)))
    }

    /// Fires a reminder immediately, bypassing the schedule. Backs the menu
    /// bar's "Remind me now" items.
    public func triggerNow(_ kind: ReminderKind) {
        guard activeReminder == nil else { return }
        present(kind, at: clock.now)
    }

    /// The user dealt with it. Logs water and starts the next cycle.
    public func acknowledge(_ kind: ReminderKind) {
        guard activeReminder == kind else { return }
        let now = clock.now
        activeReminder = nil
        activeSince = nil

        if kind == .water {
            logWater(at: now)
        }
        record(.reminderAccepted(kind), at: now)
        restartCycle(for: kind, at: now)
        onEvent?(.reminderAcknowledged(kind))
    }

    /// Push it back by the snooze interval rather than a whole cycle.
    public func snooze(_ kind: ReminderKind) {
        guard activeReminder == kind else { return }
        let now = clock.now
        activeReminder = nil
        activeSince = nil
        timers[kind]?.snooze(by: settings.snoozeInterval, at: now)
        record(.reminderSnoozed(kind), at: now)
        let until = now.addingTimeInterval(settings.snoozeInterval)
        onEvent?(.reminderSnoozed(kind, until: until))
    }

    private func timeOut(_ kind: ReminderKind, at now: Date) {
        activeReminder = nil
        activeSince = nil
        timers[kind]?.snooze(by: settings.snoozeInterval, at: now)
        record(.reminderIgnored(kind), at: now)
        onEvent?(.reminderTimedOut(kind))
    }

    private func restartCycle(for kind: ReminderKind, at now: Date) {
        guard let timer = timers[kind] else { return }
        if settings.isEnabled(kind) {
            timer.start(at: now)
            // Honour an active hold immediately, or the fresh cycle would run
            // through quiet hours until the next tick noticed.
            if holdReason != nil { timer.pause(at: now) }
        } else {
            timer.stop()
        }
    }

    // MARK: Water tracking

    /// Logs a glass outside the reminder flow (menu bar "+1 glass").
    public func logWaterManually() {
        logWater(at: clock.now)
    }

    private func logWater(at now: Date) {
        let wasAtGoal = waterLog.hasReachedGoal(settings.water)
        waterLog.add(1, at: now, calendar: calendar)
        waterLogStore?.save(waterLog)
        record(.glassLogged(goal: settings.water.glassesForGoal), at: now)
        let reachedNow = waterLog.hasReachedGoal(settings.water)
        onEvent?(.waterLogged(
            glasses: waterLog.glasses,
            goal: settings.water.glassesForGoal,
            goalJustReached: reachedNow && !wasAtGoal
        ))
    }

    // MARK: Activity history

    /// Writes an event into today's record and persists it.
    private func record(_ event: ActivityEvent, at now: Date) {
        activityLog.apply(event, at: now, calendar: calendar)
        activityLogStore?.save(activityLog)
    }

    /// Records a completed focus session. Called by the app, not the engine.
    public func recordFocusSession(minutes: Double) {
        record(.focusSessionCompleted(minutes: minutes), at: clock.now)
    }

    /// Drops hour-by-hour detail recorded before `cutoff`, keeping every daily
    /// total.
    ///
    /// Narrow on purpose. `replaceActivityLog` below would do the job, but it
    /// is a developer tool that can overwrite the entire history, and handing a
    /// production feature that much reach is how histories get lost. This can
    /// only ever remove old timestamps.
    public func clearEventDetail(before cutoff: Date) {
        var log = activityLog
        log.clearEvents(before: cutoff)
        activityLog = log
        activityLogStore?.save(log)
    }

    #if AITWIN_DEV
    /// Replaces the whole history. Used only by the developer tools.
    public func replaceActivityLog(_ log: ActivityLog) {
        activityLog = log
        activityLogStore?.save(log)
    }
    #endif

    /// Folds history from another machine into this one.
    public func mergeActivityLog(_ other: ActivityLog) {
        activityLog = activityLog.merged(with: other)
        activityLogStore?.save(activityLog)
    }

    public func currentStreak() -> Int {
        activityLog.currentStreak(endingAt: clock.now, calendar: calendar)
    }

    public func bestStreak() -> Int {
        activityLog.bestStreak(calendar: calendar)
    }

    /// The streak milestone reached by today's goal, if any.
    public func streakMilestoneReachedToday() -> Int? {
        ActivityLog.milestone(for: currentStreak())
    }

    // MARK: Settings

    /// Applies new settings, restarting any timer whose interval or enabled
    /// state changed and leaving the others running.
    public func apply(_ newSettings: AiTwinSettings) {
        let old = settings
        settings = newSettings
        let now = clock.now

        for kind in ReminderKind.allCases {
            guard let timer = timers[kind] else { continue }
            let enabled = newSettings.isEnabled(kind)
            let intervalChanged = old.interval(for: kind) != newSettings.interval(for: kind)

            if !enabled {
                timer.stop()
            } else if !timer.isActive {
                // Newly enabled: adopt the interval, then begin a fresh cycle.
                timer.setInterval(newSettings.interval(for: kind), at: now)
                timer.start(at: now)
            } else if intervalChanged {
                timer.setInterval(newSettings.interval(for: kind), at: now)
            }
        }
        if isStarted { applyHold(at: now, idleSeconds: 0) }
    }

    public func setPaused(_ paused: Bool) {
        var updated = settings
        updated.remindersPaused = paused
        apply(updated)
    }

    // MARK: Introspection (menu bar / tests)

    public func timeRemaining(for kind: ReminderKind) -> TimeInterval? {
        timers[kind]?.remaining(at: clock.now)
    }

    public func isTimerRunning(_ kind: ReminderKind) -> Bool {
        timers[kind]?.isRunning ?? false
    }

    public func deadline(for kind: ReminderKind) -> Date? {
        timers[kind]?.deadline
    }
}
