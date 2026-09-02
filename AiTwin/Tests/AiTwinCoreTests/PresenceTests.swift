import Foundation
import Testing
@testable import AiTwinCore

/// Time away from the Mac is not screen time.
///
/// The rule these lock down: a reminder measures how long you have been *at*
/// the machine, so a locked screen must not advance it, and coming back after a
/// real absence starts the count again from scratch rather than delivering a
/// reminder the instant you sit down.
@Suite("Away and back")
struct AwayTests {

    private func makeEngine(
        settings: AiTwinSettings = .defaults
    ) -> (ReminderEngine, FakeClock, EventRecorder) {
        let clock = FakeClock()
        let recorder = EventRecorder()
        var settings = settings
        settings.stretchEnabled = false
        let engine = ReminderEngine(
            settings: settings,
            clock: clock,
            calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore()
        )
        engine.onEvent = { recorder.record($0) }
        return (engine, clock, recorder)
    }

    /// Water every 20 minutes, nothing else.
    private var waterOnly: AiTwinSettings {
        var settings = AiTwinSettings.defaults
        settings.eyeBreakEnabled = false
        settings.waterInterval = 20 * 60
        return settings
    }

    @Test("locking at fifteen minutes owes a full twenty on return, not five")
    func lockRestartsTheCycle() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()

        clock.advance(15 * 60)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)

        engine.beginAway()
        clock.advance(5 * 60)
        engine.endAway(resetCycles: true)

        // The five minutes that were left before the lock are gone: they were
        // measured against a screen nobody was looking at.
        clock.advance(19 * 60)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty, "the old remainder must not fire")

        clock.advance(60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("no countdown advances while the screen is locked")
    func nothingAccruesWhileAway() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()
        engine.beginAway()

        #expect(engine.isAway)
        #expect(engine.holdReason == .away)

        clock.advance(4 * 3600)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)
        #expect(engine.holdReason == .away)
    }

    @Test("a minute fetching a coffee keeps the progress it had")
    func briefAwayKeepsProgress() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()

        clock.advance(15 * 60)
        engine.tick()
        engine.beginAway()
        clock.advance(30)
        engine.endAway(resetCycles: false)

        // Five minutes were banked, and five minutes is what is owed.
        clock.advance(5 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("being away outranks every other reason to be quiet")
    func awayOutranksPaused() {
        var settings = waterOnly
        settings.remindersPaused = true
        let (engine, _, _) = makeEngine(settings: settings)
        engine.start()
        #expect(engine.holdReason == .paused)

        engine.beginAway()
        #expect(engine.holdReason == .away)

        engine.endAway(resetCycles: true)
        #expect(engine.holdReason == .paused, "still paused once she is back")
    }

    @Test("a reset during quiet hours defers a *full* interval, not a remainder")
    func resetDuringQuietHoursIsDeferred() {
        var settings = waterOnly
        settings.quietHours = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        let (engine, clock, recorder) = makeEngine(settings: settings)
        clock.setTimeOfDay(hour: 20, minute: 0, calendar: .testUTC)
        engine.start()

        clock.advance(15 * 60)
        engine.tick()

        engine.beginAway()
        // Comes back at 23:00, inside quiet hours.
        clock.advance(3 * 3600)
        engine.endAway(resetCycles: true)
        engine.tick()
        #expect(engine.holdReason == .quietHours)
        #expect(recorder.dueReminders.isEmpty)

        // 07:00, quiet hours over. The banked amount must be the whole
        // interval -- not the five minutes that were left before the lock.
        clock.advance(8 * 3600)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty, "a full interval is owed from now")

        clock.advance(20 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("a burst of lock notifications acts once")
    func beginAwayIsIdempotent() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()
        clock.advance(15 * 60)
        engine.tick()

        engine.beginAway()
        clock.advance(60)
        engine.beginAway()   // a lid close fires several notifications
        engine.beginAway()
        engine.endAway(resetCycles: true)

        clock.advance(20 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("coming back without having gone away changes nothing")
    func endAwayWithoutBeginIsANoOp() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()
        clock.advance(15 * 60)
        engine.tick()

        engine.endAway(resetCycles: true)
        #expect(engine.isAway == false)

        // The cycle was never restarted, so the original deadline still stands.
        clock.advance(5 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("a reminder on screen when the Mac locks is taken down, not left up")
    func activeReminderIsWithdrawn() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()
        clock.advance(20 * 60)
        engine.tick()
        #expect(engine.activeReminder == .water)

        engine.beginAway()
        #expect(engine.activeReminder == nil)
        #expect(recorder.events.contains(.reminderWithdrawn(.water)))
    }

    @Test("a withdrawn reminder asks again a full interval after you return")
    func withdrawnReminderDoesNotFireOnUnlock() {
        let (engine, clock, recorder) = makeEngine(settings: waterOnly)
        engine.start()
        clock.advance(20 * 60)
        engine.tick()
        engine.beginAway()

        clock.advance(30 * 60)
        engine.endAway(resetCycles: true)
        engine.tick()
        // The whole point: she does not pounce the moment you sit down. One
        // reminder was raised before the lock; there must not be a second yet.
        #expect(recorder.dueReminders == [.water])

        clock.advance(20 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water, .water])
    }
}

@Suite("PresenceTracker")
struct PresenceTrackerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a long absence is worth resetting for")
    func significantAbsence() {
        var tracker = PresenceTracker()
        let noted = tracker.noteAway(at: start)
        #expect(noted)
        #expect(tracker.isAway)
        let outcome = tracker.noteBack(at: start.addingTimeInterval(300))
        #expect(outcome == .significant(300))
        #expect(tracker.isAway == false)
    }

    @Test("a quick lock is not a return")
    func briefAbsence() {
        var tracker = PresenceTracker()
        tracker.noteAway(at: start)
        let outcome = tracker.noteBack(at: start.addingTimeInterval(20))
        #expect(outcome == .brief(20))
    }

    @Test("exactly at the threshold counts as significant")
    func boundary() {
        var atThreshold = PresenceTracker()
        atThreshold.noteAway(at: start)
        let exact = atThreshold.noteBack(at: start.addingTimeInterval(60))
        #expect(exact == .significant(60))

        var justUnder = PresenceTracker()
        justUnder.noteAway(at: start)
        let under = justUnder.noteBack(at: start.addingTimeInterval(59.9))
        if case .brief(let elapsed) = under {
            #expect(abs(elapsed - 59.9) < 0.001)
        } else {
            Issue.record("just under the threshold must be brief, got \(under)")
        }
    }

    @Test("a second away signal is ignored, so a burst acts once")
    func repeatedAwayIsIgnored() {
        var tracker = PresenceTracker()
        let first = tracker.noteAway(at: start)
        let second = tracker.noteAway(at: start.addingTimeInterval(1))
        #expect(first)
        #expect(second == false)
        // The absence is still measured from the first signal.
        let outcome = tracker.noteBack(at: start.addingTimeInterval(90))
        #expect(outcome == .significant(90))
    }

    @Test("coming back without leaving is ignored entirely")
    func spuriousReturn() {
        var tracker = PresenceTracker()
        let outcome = tracker.noteBack(at: start)
        #expect(outcome == .spurious)
    }

    @Test("a clock that jumped backwards cannot produce a negative absence")
    func backwardsClock() {
        var tracker = PresenceTracker()
        tracker.noteAway(at: start)
        let outcome = tracker.noteBack(at: start.addingTimeInterval(-500))
        #expect(outcome == .brief(0))
    }
}
