import Foundation
import Testing
@testable import AiTwinCore

@Suite("ReminderEngine")
struct ReminderEngineTests {

    /// Builds an engine wired to a fake clock and an event recorder.
    private func makeEngine(
        settings: AiTwinSettings = .defaults,
        configuration: AiTwinConfiguration = .production
    ) -> (ReminderEngine, FakeClock, EventRecorder) {
        let clock = FakeClock()
        let recorder = EventRecorder()
        var settings = settings
        // Stretch is a third reminder kind; tests that predate it isolate on
        // water and eye breaks, so keep it quiet unless a test enables it.
        if settings.stretchInterval == AiTwinSettings.defaults.stretchInterval {
            settings.stretchEnabled = false
        }
        let engine = ReminderEngine(
            settings: settings,
            configuration: configuration,
            clock: clock,
            calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore()
        )
        engine.onEvent = { recorder.record($0) }
        return (engine, clock, recorder)
    }

    // MARK: Launch

    @Test("launching starts both timers")
    func launchInitializesTimers() {
        let (engine, _, _) = makeEngine()
        engine.start()
        #expect(engine.isTimerRunning(.water))
        #expect(engine.isTimerRunning(.eyeBreak))
    }

    @Test("a disabled reminder never starts a timer")
    func disabledReminderDoesNotStart() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        #expect(engine.isTimerRunning(.water) == false)
        clock.advance(10_000)
        engine.tick()
        #expect(recorder.dueReminders.contains(.water) == false)
    }

    @Test("nothing fires before its interval")
    func nothingFiresEarly() {
        let (engine, clock, recorder) = makeEngine()
        engine.start()

        clock.advance(60)
        engine.tick()
        #expect(recorder.events.isEmpty)
    }

    // MARK: The 40-minute eye break

    @Test("the eye break fires after exactly 40 minutes")
    func eyeBreakFiresAt40Minutes() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false   // isolate the eye-break timer
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(40 * 60 - 1)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)

        clock.advance(1)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    @Test("acknowledging an eye break starts the next 40-minute cycle")
    func eyeBreakCycleRepeats() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(40 * 60)
        engine.tick()
        engine.acknowledge(.eyeBreak)
        #expect(engine.activeReminder == nil)

        clock.advance(40 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak, .eyeBreak])
    }

    // MARK: Water

    @Test("the water reminder fires at its own interval")
    func waterFiresAtInterval() {
        var settings = AiTwinSettings.defaults
        settings.eyeBreakEnabled = false
        settings.waterInterval = 45 * 60
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(45 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("acknowledging a water reminder logs a glass")
    func waterAcknowledgementLogsGlass() {
        let (engine, clock, _) = makeEngine()
        engine.start()
        #expect(engine.waterLog.glasses == 0)

        clock.advance(45 * 60)
        engine.tick()
        engine.acknowledge(.water)
        #expect(engine.waterLog.glasses == 1)
    }

    @Test("acknowledging an eye break does not log water")
    func eyeBreakDoesNotLogWater() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, _) = makeEngine(settings: settings)
        engine.start()

        clock.advance(40 * 60)
        engine.tick()
        engine.acknowledge(.eyeBreak)
        #expect(engine.waterLog.glasses == 0)
    }

    @Test("reaching the daily goal is reported exactly once")
    func goalReachedOnce() {
        var settings = AiTwinSettings.defaults
        settings.water = WaterIntake(glassSize: 250, dailyGoal: 500)
        let (engine, _, recorder) = makeEngine(settings: settings)
        engine.start()

        engine.logWaterManually()
        engine.logWaterManually()
        engine.logWaterManually()

        let goalEvents = recorder.events.filter {
            if case .waterLogged(_, _, let justReached) = $0 { return justReached }
            return false
        }
        #expect(goalEvents.count == 1)
        #expect(engine.waterLog.glasses == 3)
    }

    @Test("the water count resets on a new day")
    func waterResetsDaily() {
        let (engine, clock, _) = makeEngine()
        engine.start()
        engine.logWaterManually()
        #expect(engine.waterLog.glasses == 1)

        clock.advance(24 * 3600)
        engine.tick()
        #expect(engine.waterLog.glasses == 0)
    }

    // MARK: Snooze

    @Test("snooze reschedules by the snooze interval, not a whole cycle")
    func snoozeUsesSnoozeInterval() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.snoozeInterval = 5 * 60
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(40 * 60)
        engine.tick()
        engine.snooze(.eyeBreak)

        clock.advance(5 * 60 - 1)
        engine.tick()
        #expect(recorder.dueReminders.count == 1)

        clock.advance(1)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak, .eyeBreak])
    }

    @Test("snooze only affects the snoozed reminder")
    func snoozeTouchesOneTimer() {
        var settings = AiTwinSettings.defaults
        settings.waterInterval = 100
        settings.eyeBreakInterval = 10_000
        settings.snoozeInterval = 50
        let (engine, clock, _) = makeEngine(settings: settings)
        engine.start()

        let eyeDeadlineBefore = engine.deadline(for: .eyeBreak)
        clock.advance(100)
        engine.tick()
        engine.snooze(.water)

        #expect(engine.deadline(for: .eyeBreak) == eyeDeadlineBefore)
        #expect(engine.deadline(for: .water) == clock.now.addingTimeInterval(50))
    }

    @Test("snoozing a reminder that is not showing does nothing")
    func snoozeIgnoredWhenNotActive() {
        let (engine, _, recorder) = makeEngine()
        engine.start()
        engine.snooze(.water)
        #expect(recorder.events.isEmpty)
    }

    // MARK: One at a time

    @Test("only one reminder shows at a time")
    func oneReminderAtATime() {
        var settings = AiTwinSettings.defaults
        settings.waterInterval = 60
        settings.eyeBreakInterval = 60
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(60)
        engine.tick()
        engine.tick()
        engine.tick()
        #expect(recorder.dueReminders == [.water])
        #expect(engine.activeReminder == .water)
    }

    @Test("the second reminder appears once the first is acknowledged")
    func secondReminderFollows() {
        var settings = AiTwinSettings.defaults
        settings.waterInterval = 60
        settings.eyeBreakInterval = 60
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(60)
        engine.tick()
        engine.acknowledge(.water)
        engine.tick()
        #expect(recorder.dueReminders == [.water, .eyeBreak])
    }

    @Test("an unanswered reminder times out and reschedules")
    func reminderTimesOut() {
        var config = AiTwinConfiguration.production
        config.reminderTimeout = 60
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, recorder) = makeEngine(settings: settings, configuration: config)
        engine.start()

        clock.advance(40 * 60)
        engine.tick()
        #expect(engine.activeReminder == .eyeBreak)

        clock.advance(60)
        engine.tick()
        #expect(engine.activeReminder == nil)
        #expect(recorder.events.contains(.reminderTimedOut(.eyeBreak)))
    }

    // MARK: Pause

    @Test("pausing stops reminders from firing")
    func pauseStopsReminders() {
        let (engine, clock, recorder) = makeEngine()
        engine.start()
        engine.setPaused(true)

        clock.advance(10 * 3600)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)
        #expect(engine.holdReason == .paused)
    }

    @Test("resuming keeps the progress made before pausing")
    func resumeKeepsProgress() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(39 * 60)
        engine.tick()
        engine.setPaused(true)
        clock.advance(10 * 3600)
        engine.tick()
        engine.setPaused(false)

        // One minute of the original 40 remains -- not a whole new cycle.
        clock.advance(60)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    // MARK: Idle

    @Test("time away from the keyboard does not count as screen time")
    func idleSuspendsCountdown() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.pauseWhenIdle = true
        settings.idleThreshold = 300
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(20 * 60)
        engine.tick(idleSeconds: 0)

        // Away for two hours: the eye-break clock should not advance.
        clock.advance(2 * 3600)
        engine.tick(idleSeconds: 2 * 3600)
        #expect(engine.holdReason == .userIdle)
        #expect(recorder.dueReminders.isEmpty)

        // Back at the keyboard: the remaining 20 minutes still has to elapse.
        engine.tick(idleSeconds: 0)
        clock.advance(20 * 60)
        engine.tick(idleSeconds: 0)
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    @Test("idle pausing can be turned off")
    func idlePauseDisabled() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.pauseWhenIdle = false
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        clock.advance(40 * 60)
        engine.tick(idleSeconds: 40 * 60)
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    // MARK: Quiet hours

    @Test("no reminders fire during quiet hours")
    func quietHoursSuppress() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.quietHours = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        let (engine, clock, recorder) = makeEngine(settings: settings)

        clock.setTimeOfDay(hour: 23)
        engine.start()
        clock.advance(40 * 60)
        engine.tick()

        #expect(engine.holdReason == .quietHours)
        #expect(recorder.dueReminders.isEmpty)
    }

    @Test("reminders resume after quiet hours end")
    func quietHoursRelease() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.quietHours = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        let (engine, clock, recorder) = makeEngine(settings: settings)

        clock.setTimeOfDay(hour: 23)
        engine.start()
        clock.advance(3 * 3600)     // 02:00, still quiet
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)

        clock.setTimeOfDay(hour: 9)  // out of quiet hours
        engine.tick()
        #expect(engine.holdReason == nil)
        clock.advance(40 * 60)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    // MARK: Settings changes

    @Test("test mode intervals take effect without waiting out the old one")
    func switchingToTestIntervals() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()
        clock.advance(60)

        settings.eyeBreakInterval = 10
        engine.apply(settings)

        clock.advance(10)
        engine.tick()
        #expect(recorder.dueReminders == [.eyeBreak])
    }

    @Test("changing one interval leaves the other timer alone")
    func changingOneIntervalPreservesTheOther() {
        var settings = AiTwinSettings.defaults
        settings.waterInterval = 1000
        settings.eyeBreakInterval = 2000
        let (engine, clock, _) = makeEngine(settings: settings)
        engine.start()

        let waterDeadline = engine.deadline(for: .water)
        clock.advance(100)
        settings.eyeBreakInterval = 500
        engine.apply(settings)

        #expect(engine.deadline(for: .water) == waterDeadline)
        #expect(engine.deadline(for: .eyeBreak) == clock.now.addingTimeInterval(500))
    }

    @Test("enabling a reminder that was off starts its timer")
    func enablingStartsTimer() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.waterInterval = 100
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()
        #expect(engine.isTimerRunning(.water) == false)

        settings.waterEnabled = true
        engine.apply(settings)
        #expect(engine.isTimerRunning(.water))

        clock.advance(100)
        engine.tick()
        #expect(recorder.dueReminders.contains(.water))
    }

    @Test("disabling a reminder mid-cycle stops it")
    func disablingStopsTimer() {
        var settings = AiTwinSettings.defaults
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        settings.waterEnabled = false
        settings.eyeBreakEnabled = false
        settings.stretchEnabled = false
        engine.apply(settings)

        clock.advance(10 * 3600)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)
    }

    // MARK: Manual trigger

    @Test("trigger now fires immediately")
    func triggerNow() {
        let (engine, _, recorder) = makeEngine()
        engine.start()
        engine.triggerNow(.water)
        #expect(recorder.dueReminders == [.water])
        #expect(engine.activeReminder == .water)
    }

    @Test("trigger now is ignored while a reminder is already showing")
    func triggerNowIgnoredWhenBusy() {
        let (engine, _, recorder) = makeEngine()
        engine.start()
        engine.triggerNow(.water)
        engine.triggerNow(.eyeBreak)
        #expect(recorder.dueReminders == [.water])
    }

    @Test("ticking before start does nothing")
    func tickBeforeStart() {
        let (engine, clock, recorder) = makeEngine()
        clock.advance(10 * 3600)
        engine.tick()
        #expect(recorder.events.isEmpty)
    }

    @Test("every reminder message is used before any repeats")
    func messagesDoNotRepeat() {
        var settings = AiTwinSettings.defaults
        settings.eyeBreakEnabled = false
        settings.waterInterval = 10
        let (engine, clock, recorder) = makeEngine(settings: settings)
        engine.start()

        // With no name set, the lines that require one are not offered.
        let poolSize = MessageCatalog.usable(MessageCatalog.waterMessages, hasName: false).count
        var seen: [String] = []
        for _ in 0..<poolSize {
            clock.advance(10)
            engine.tick()
            if let message = recorder.lastMessage { seen.append(message) }
            engine.acknowledge(.water)
        }
        #expect(Set(seen).count == poolSize)
    }
}
