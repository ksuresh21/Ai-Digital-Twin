import Foundation
import Testing
@testable import AiTwinCore

@Suite("Activity log and streaks")
struct ActivityLogTests {

    private let calendar = Calendar.testUTC
    private var day0: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0)!
    }

    private func log(goalMetOn offsets: [Int], goal: Int = 2) -> ActivityLog {
        var log = ActivityLog()
        for offset in offsets {
            for _ in 0..<goal {
                log.apply(.glassLogged(goal: goal), at: day(offset), calendar: calendar)
            }
        }
        return log
    }

    @Test("a glass is recorded against the right day")
    func recordsGlasses() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(log.record(on: day(0), calendar: calendar)?.glasses == 2)
        #expect(log.record(on: day(1), calendar: calendar) == nil)
    }

    @Test("the goal in force that day is stored with it")
    func storesGoalPerDay() {
        // Changing the goal later must not retroactively fail an earlier day.
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 2), at: day(0), calendar: calendar)
        log.apply(.glassLogged(goal: 2), at: day(0), calendar: calendar)
        #expect(log.record(on: day(0), calendar: calendar)?.metWaterGoal == true)
        log.apply(.glassLogged(goal: 10), at: day(1), calendar: calendar)
        #expect(log.record(on: day(0), calendar: calendar)?.metWaterGoal == true)
        #expect(log.record(on: day(1), calendar: calendar)?.metWaterGoal == false)
    }

    @Test("eye breaks are tracked as taken, snoozed and missed")
    func tracksBreakOutcomes() {
        var log = ActivityLog()
        log.apply(.reminderAccepted(.eyeBreak), at: day(0), calendar: calendar)
        log.apply(.reminderAccepted(.eyeBreak), at: day(0), calendar: calendar)
        log.apply(.reminderSnoozed(.eyeBreak), at: day(0), calendar: calendar)
        log.apply(.reminderIgnored(.eyeBreak), at: day(0), calendar: calendar)
        let record = log.record(on: day(0), calendar: calendar)!
        #expect(record.eyeBreaksAccepted == 2)
        #expect(record.eyeBreaksSnoozed == 1)
        #expect(record.eyeBreaksIgnored == 1)
        #expect(record.breaksOffered == 4)
        #expect(record.breakAcceptanceRate == 0.5)
    }

    @Test("stretches are tracked separately from eye breaks")
    func stretchesTrackedSeparately() {
        var log = ActivityLog()
        log.apply(.reminderAccepted(.stretch), at: day(0), calendar: calendar)
        log.apply(.reminderAccepted(.eyeBreak), at: day(0), calendar: calendar)
        let record = log.record(on: day(0), calendar: calendar)!
        #expect(record.stretchesAccepted == 1)
        #expect(record.eyeBreaksAccepted == 1)
    }

    @Test("a day with no breaks offered has no acceptance rate")
    func noRateWithoutOffers() {
        // Charting an untouched day as 0% would be a lie.
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(log.record(on: day(0), calendar: calendar)?.breakAcceptanceRate == nil)
    }

    @Test("focus sessions accumulate minutes")
    func focusMinutes() {
        var log = ActivityLog()
        log.apply(.focusSessionCompleted(minutes: 25), at: day(0), calendar: calendar)
        log.apply(.focusSessionCompleted(minutes: 25), at: day(0), calendar: calendar)
        let record = log.record(on: day(0), calendar: calendar)!
        #expect(record.focusSessionsCompleted == 2)
        #expect(record.focusMinutes == 50)
    }

    // MARK: Streaks

    @Test("consecutive goal days build a streak")
    func streakCounts() {
        let log = self.log(goalMetOn: [-2, -1, 0])
        #expect(log.currentStreak(endingAt: day(0), calendar: calendar) == 3)
    }

    @Test("an unfinished today does not break yesterday's streak")
    func todayInProgressKeepsStreak() {
        // Otherwise every morning would show a zero and the number would be
        // useless before lunch.
        let log = self.log(goalMetOn: [-3, -2, -1])
        #expect(log.currentStreak(endingAt: day(0), calendar: calendar) == 3)
    }

    @Test("a fully missed day breaks the streak")
    func missedDayBreaksStreak() {
        let log = self.log(goalMetOn: [-4, -3, -1])
        // Day -2 was missed, so only day -1 counts.
        #expect(log.currentStreak(endingAt: day(0), calendar: calendar) == 1)
    }

    @Test("an empty log has no streak")
    func emptyLogNoStreak() {
        #expect(ActivityLog().currentStreak(endingAt: day(0), calendar: calendar) == 0)
        #expect(ActivityLog().bestStreak(calendar: calendar) == 0)
    }

    @Test("the best streak survives being broken later")
    func bestStreakRemembered() {
        let log = self.log(goalMetOn: [-9, -8, -7, -6, -3, -2])
        #expect(log.bestStreak(calendar: calendar) == 4)
        #expect(log.currentStreak(endingAt: day(0), calendar: calendar) == 0)
    }

    @Test("milestones are recognised only on the exact day")
    func milestones() {
        #expect(ActivityLog.milestone(for: 3) == 3)
        #expect(ActivityLog.milestone(for: 7) == 7)
        #expect(ActivityLog.milestone(for: 4) == nil)
        #expect(ActivityLog.milestone(for: 0) == nil)
    }

    // MARK: Windows and retention

    @Test("a week always has seven days, including empty ones")
    func weekIsAlwaysFull() {
        // A chart with gaps would be unreadable.
        let log = self.log(goalMetOn: [0])
        let week = log.recentDays(7, endingAt: day(0), calendar: calendar)
        #expect(week.count == 7)
        #expect(week.last?.dayStart == day(0))
        #expect(week.first?.dayStart == day(-6))
    }

    @Test("daily summaries are kept indefinitely")
    func keepsDailySummariesForever() {
        // These used to be pruned at ninety days. They are not any more: a
        // day's summary is a couple of hundred bytes, so twenty years is about
        // 1.5 MB, and dropping them capped the best streak at the length of
        // the retention window. Only the timestamped detail is ever cleared.
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: day(-200), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(log.days.count == 2)
        #expect(log.days.first?.dayStart == day(-200))
        #expect(log.days.last?.dayStart == day(0))
    }

    @Test("only days with activity are stored")
    func noEmptyRows() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(log.days.count == 1)
    }

    @Test("the log round-trips through storage")
    func roundTrip() throws {
        let log = self.log(goalMetOn: [-1, 0])
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(ActivityLog.self, from: data) == log)
    }

    @Test("corrupt stored history falls back to empty rather than crashing")
    func corruptHistory() {
        let defaults = UserDefaults(suiteName: "com.aitwin.tests.activity")!
        defaults.removePersistentDomain(forName: "com.aitwin.tests.activity")
        defaults.set(Data("not json".utf8), forKey: "k")
        let store = UserDefaultsActivityLogStore(defaults: defaults, key: "k")
        #expect(store.load().days.isEmpty)
    }

    // MARK: Merging across machines

    @Test("merging takes the higher count per day")
    func mergeTakesMax() {
        // Both Macs saw the same glass; summing would double-count it.
        var a = ActivityLog(); var b = ActivityLog()
        a.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        a.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        b.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(a.merged(with: b).record(on: day(0), calendar: calendar)?.glasses == 2)
    }

    @Test("merging keeps days only one machine has")
    func mergeKeepsBothDays() {
        var a = ActivityLog(); var b = ActivityLog()
        a.apply(.glassLogged(goal: 8), at: day(-1), calendar: calendar)
        b.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar)
        #expect(a.merged(with: b).days.count == 2)
    }

    @Test("merging is order-independent")
    func mergeIsSymmetric() {
        var a = ActivityLog(); var b = ActivityLog()
        a.apply(.reminderAccepted(.eyeBreak), at: day(0), calendar: calendar)
        b.apply(.reminderSnoozed(.eyeBreak), at: day(0), calendar: calendar)
        #expect(a.merged(with: b) == b.merged(with: a))
    }
}

@Suite("Focus sessions")
struct FocusSessionTests {

    private func make(_ settings: AiTwinSettings = .defaults) -> (FocusController, FakeClock) {
        let clock = FakeClock()
        return (FocusController(settings: settings, clock: clock), clock)
    }

    @Test("a controller starts inactive")
    func startsInactive() {
        let (focus, _) = make()
        #expect(focus.isActive == false)
        #expect(focus.isWorking == false)
    }

    @Test("starting begins a working phase of the configured length")
    func startsWorking() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 25 * 60
        let (focus, _) = make(settings)
        focus.start()
        #expect(focus.session?.phase == .working)
        #expect(focus.session?.duration == TimeInterval(25 * 60))
        #expect(focus.isWorking)
    }

    @Test("work rolls into a short break")
    func workThenBreak() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 60
        settings.focusBreakLength = 30
        let (focus, clock) = make(settings)
        focus.start()

        clock.advance(60)
        focus.tick()
        #expect(focus.session?.phase == .shortBreak)
        #expect(focus.session?.duration == 30)
        // A break must NOT suppress reminders -- that is when held ones arrive.
        #expect(focus.isWorking == false)
        #expect(focus.completedSessions == 1)
    }

    @Test("a long break follows the configured number of sessions")
    func longBreakAfterSet() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 10
        settings.focusBreakLength = 5
        settings.focusLongBreakLength = 20
        settings.sessionsBeforeLongBreak = 2
        let (focus, clock) = make(settings)
        focus.start()

        clock.advance(10); focus.tick()          // session 1 done -> short break
        #expect(focus.session?.phase == .shortBreak)
        clock.advance(5); focus.tick()           // break done -> work
        #expect(focus.session?.phase == .working)
        clock.advance(10); focus.tick()          // session 2 done -> long break
        #expect(focus.session?.phase == .longBreak)
        #expect(focus.session?.duration == 20)
    }

    @Test("completed sessions are reported for the stats log")
    func reportsCompletion() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 25 * 60
        let (focus, clock) = make(settings)
        var minutes: [Double] = []
        focus.onSessionCompleted = { minutes.append($0) }
        focus.start()
        clock.advance(25 * 60)
        focus.tick()
        #expect(minutes == [25])
    }

    @Test("a break completing reports nothing to stats")
    func breaksAreNotSessions() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 10
        settings.focusBreakLength = 5
        let (focus, clock) = make(settings)
        var count = 0
        focus.onSessionCompleted = { _ in count += 1 }
        focus.start()
        clock.advance(10); focus.tick()
        clock.advance(5); focus.tick()
        #expect(count == 1)
    }

    @Test("skipping moves to the next phase immediately")
    func skip() {
        var settings = AiTwinSettings.defaults
        settings.focusSessionLength = 25 * 60
        let (focus, _) = make(settings)
        focus.start()
        focus.skip()
        #expect(focus.session?.phase == .shortBreak)
    }

    @Test("stopping clears everything")
    func stop() {
        let (focus, _) = make()
        focus.start()
        focus.stop()
        #expect(focus.session == nil)
        #expect(focus.isActive == false)
        #expect(focus.completedSessions == 0)
    }

    @Test("ticking when nothing is running is harmless")
    func tickWhileInactive() {
        let (focus, clock) = make()
        clock.advance(10_000)
        focus.tick()
        #expect(focus.session == nil)
    }

    @Test("the countdown text reads as minutes and seconds")
    func clockText() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(phase: .working, duration: 25 * 60, startedAt: start, completedSessions: 0)
        #expect(session.clockText(at: start) == "25:00")
        #expect(session.clockText(at: start.addingTimeInterval(60)) == "24:00")
        #expect(session.clockText(at: start.addingTimeInterval(24 * 60 + 31)) == "0:29")
        #expect(session.clockText(at: start.addingTimeInterval(25 * 60)) == "0:00")
    }

    @Test("a zero-length session does not divide by zero")
    func zeroLength() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(phase: .working, duration: 0, startedAt: start, completedSessions: 0)
        #expect(session.progress(at: start) == 1)
        #expect(session.isFinished(at: start))
    }
}

@Suite("Idle chatter limits")
struct ChatterTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("chatter is allowed when nothing objects")
    func allowsWhenClear() {
        let scheduler = ChatterScheduler(frequency: .rare)
        #expect(scheduler.shouldChatter(at: now, conditions: .init()))
    }

    @Test("turning it off silences her completely")
    func offMeansOff() {
        let scheduler = ChatterScheduler(frequency: .off)
        #expect(scheduler.shouldChatter(at: now, conditions: .init()) == false)
    }

    @Test("she waits out the minimum gap between lines")
    func respectsGap() {
        var scheduler = ChatterScheduler(frequency: .rare)
        scheduler.noteChatter(at: now)
        #expect(scheduler.shouldChatter(at: now.addingTimeInterval(89 * 60), conditions: .init()) == false)
        #expect(scheduler.shouldChatter(at: now.addingTimeInterval(91 * 60), conditions: .init()))
    }

    @Test("occasional talks more often than rare")
    func frequencyOrdering() {
        #expect(ChatterScheduler.Frequency.occasional.minimumGap < ChatterScheduler.Frequency.rare.minimumGap)
        #expect(ChatterScheduler.Frequency.off.minimumGap == .infinity)
    }

    @Test("she never chats right after a reminder")
    func quietAroundReminders() {
        // Being nudged and then chatted at reads as pestering.
        var scheduler = ChatterScheduler(frequency: .rare)
        scheduler.noteReminder(at: now)
        #expect(scheduler.shouldChatter(at: now.addingTimeInterval(5 * 60), conditions: .init()) == false)
        #expect(scheduler.shouldChatter(at: now.addingTimeInterval(11 * 60), conditions: .init()))
    }

    @Test("every condition can veto on its own")
    func eachConditionVetoes() {
        let scheduler = ChatterScheduler(frequency: .occasional)
        #expect(scheduler.shouldChatter(at: now, conditions: .init(isPaused: true)) == false)
        #expect(scheduler.shouldChatter(at: now, conditions: .init(inQuietHours: true)) == false)
        #expect(scheduler.shouldChatter(at: now, conditions: .init(isFocusing: true)) == false)
        #expect(scheduler.shouldChatter(at: now, conditions: .init(characterIsBusy: true)) == false)
        #expect(scheduler.shouldChatter(at: now, conditions: .init(idleSeconds: 10 * 60)) == false)
    }

    @Test("she does not talk to an empty chair")
    func silentWhenAway() {
        let scheduler = ChatterScheduler(frequency: .occasional)
        let justUnder = ChatterScheduler.maximumIdleSeconds - 1
        #expect(scheduler.shouldChatter(at: now, conditions: .init(idleSeconds: justUnder)))
        #expect(scheduler.shouldChatter(at: now, conditions: .init(idleSeconds: justUnder + 2)) == false)
    }
}

@Suite("Stretch reminders")
struct StretchReminderTests {

    @Test("stretch is a full reminder kind")
    func isAReminderKind() {
        #expect(ReminderKind.allCases.contains(.stretch))
        #expect(ReminderKind.stretch.clipName == ClipName.stretch)
        #expect(!ReminderKind.stretch.acknowledgeTitle.isEmpty)
    }

    @Test("stretch has its own interval and toggle")
    func ownSettings() {
        var settings = AiTwinSettings.defaults
        #expect(settings.interval(for: .stretch) == 60 * 60)
        #expect(settings.isEnabled(.stretch))
        settings.stretchEnabled = false
        #expect(settings.isEnabled(.stretch) == false)
    }

    @Test("stretch fires on its own schedule")
    func firesIndependently() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.eyeBreakEnabled = false
        settings.stretchInterval = 100
        let clock = FakeClock()
        let recorder = EventRecorder()
        let engine = ReminderEngine(
            settings: settings, clock: clock, calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore(),
            activityLogStore: InMemoryActivityLogStore()
        )
        engine.onEvent = { recorder.record($0) }
        engine.start()

        clock.advance(99)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)
        clock.advance(1)
        engine.tick()
        #expect(recorder.dueReminders == [.stretch])
    }

    @Test("accepting a stretch is recorded in the history")
    func recordsAcceptance() {
        var settings = AiTwinSettings.defaults
        settings.waterEnabled = false
        settings.eyeBreakEnabled = false
        settings.stretchInterval = 10
        let clock = FakeClock()
        let engine = ReminderEngine(
            settings: settings, clock: clock, calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore(),
            activityLogStore: InMemoryActivityLogStore()
        )
        engine.start()
        clock.advance(10)
        engine.tick()
        engine.acknowledge(.stretch)
        #expect(engine.activityLog.record(on: clock.now, calendar: .testUTC)?.stretchesAccepted == 1)
    }
}

@Suite("Focus suppresses reminders")
struct FocusSuppressionTests {

    @Test("nothing fires while focusing, and the deadline is preserved")
    func heldNotDropped() {
        var settings = AiTwinSettings.defaults
        settings.eyeBreakEnabled = false
        settings.stretchEnabled = false
        settings.waterInterval = 100
        let clock = FakeClock()
        let recorder = EventRecorder()
        let engine = ReminderEngine(
            settings: settings, clock: clock, calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore(),
            activityLogStore: InMemoryActivityLogStore()
        )
        engine.onEvent = { recorder.record($0) }
        engine.start()

        clock.advance(50)
        engine.tick()
        engine.isFocusing = true

        // A whole focus session passes; nothing interrupts.
        clock.advance(25 * 60)
        engine.tick()
        #expect(recorder.dueReminders.isEmpty)
        #expect(engine.holdReason == .focusing)

        // The break begins: the remaining 50 seconds still has to elapse, and
        // then the held reminder arrives.
        engine.isFocusing = false
        engine.tick()
        clock.advance(50)
        engine.tick()
        #expect(recorder.dueReminders == [.water])
    }

    @Test("focus outranks quiet hours as the reported reason")
    func focusReasonWins() {
        var settings = AiTwinSettings.defaults
        settings.quietHours = QuietHours(isEnabled: true, startMinutes: 0, endMinutes: 1439)
        let clock = FakeClock()
        let engine = ReminderEngine(
            settings: settings, clock: clock, calendar: .testUTC,
            waterLogStore: InMemoryWaterLogStore()
        )
        engine.start()
        engine.isFocusing = true
        engine.tick()
        #expect(engine.holdReason == .focusing)
    }

    @Test("a pause still outranks focus")
    func pauseWins() {
        let clock = FakeClock()
        var settings = AiTwinSettings.defaults
        settings.remindersPaused = true
        let engine = ReminderEngine(settings: settings, clock: clock, calendar: .testUTC)
        engine.start()
        engine.isFocusing = true
        engine.tick()
        #expect(engine.holdReason == .paused)
    }

    @Test("every hold reason explains itself in the menu bar")
    func holdReasonsHaveText() {
        // allCases, not a hand-written list: the hand-written one silently
        // skipped `.away` the day it was added.
        for reason in EngineHoldReason.allCases {
            #expect(!reason.displayName.isEmpty)
        }
    }
}

@Suite("New character states")
struct NewStateTests {

    @Test("chatter lands in one state, with no separate arrival")
    func chatterPeeks() {
        #expect(SummonPurpose.chatter.entrance == .slide)
        let machine = CharacterStateMachine()
        machine.handle(.summon(.chatter))
        // Straight to .chattering. Routing through .appearing first meant a
        // silent pop-in at the corner, then 0.9s later the window jumping to
        // the screen edge as the message arrived -- one summon that looked
        // like two separate visits.
        #expect(machine.state == .chattering)
        #expect(machine.state.clipName == ClipName.peek)
        #expect(machine.state.isWalking == false)
    }

    @Test("previewing the peek slides in like the real thing")
    func peekPreviewSlides() {
        // The Developer tab is where this behaviour gets checked, so a preview
        // that popped at the resting corner and walked off was showing a
        // placement and an exit the feature does not have.
        #expect(SummonPurpose.preview(ClipName.peek).entrance == .slide)
        #expect(SummonPurpose.previewSequence(ClipSequence.peekRoutine.name).entrance == .slide)

        let machine = CharacterStateMachine()
        machine.handle(.summon(.preview(ClipName.peek)))
        #expect(machine.state == .previewing(clip: ClipName.peek))
    }

    @Test("previewing anything else still pops at the corner")
    func otherPreviewsPop() {
        #expect(SummonPurpose.preview(ClipName.cheer).entrance == .pop)
        #expect(SummonPurpose.preview(ClipName.idle).entrance == .pop)
        #expect(SummonPurpose.previewSequence(ClipSequence.greetingRoutine.name).entrance == .pop)

        let machine = CharacterStateMachine()
        machine.handle(.summon(.preview(ClipName.cheer)))
        #expect(machine.state == .appearing(.preview(ClipName.cheer)))
    }

    @Test("a chatter interrupted mid-visit still re-enters cleanly")
    func chatterFromLeaving() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.chatter))
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
        machine.handle(.summon(.chatter))
        #expect(machine.state == .chattering)
    }

    @Test("chatter goes away on its own")
    func chatterLeaves() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.chatter))
        machine.handle(.arrivedAtCorner)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("a reminder interrupts chatter")
    func reminderBeatsChatter() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.chatter))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }

    @Test("focusing uses the reading clip")
    func focusState() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.focus))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .focusing)
        #expect(machine.state.clipName == ClipName.focus)
    }

    @Test("a focus session does not time out on its own")
    func focusIgnoresRestTimeout() {
        // She sits for the whole session; only an explicit end moves her.
        let machine = CharacterStateMachine()
        machine.handle(.summon(.focus))
        machine.handle(.arrivedAtCorner)
        machine.handle(.restTimeout)
        #expect(machine.state == .focusing)
        machine.handle(.focusFinished)
        #expect(machine.state == .leaving)
    }

    @Test("previewing plays any named clip")
    func previewState() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.preview(ClipName.yawn)))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .previewing(clip: ClipName.yawn))
        #expect(machine.state.clipName == ClipName.yawn)
    }

    @Test("previewing another clip swaps straight over")
    func previewSwaps() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.preview(ClipName.yawn)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.preview(ClipName.cheer)))
        #expect(machine.state == .previewing(clip: ClipName.cheer))
    }

    @Test("all the new mood clips are registered for loading")
    func moodClipsRegistered() {
        for clip in [ClipName.concerned, ClipName.cheer, ClipName.peek, ClipName.yawn,
                     ClipName.focus, ClipName.stretch, ClipName.sitting] {
            #expect(ClipName.loadable.contains(clip), "\(clip) not loadable")
            #expect(ClipDefinition.standard.contains { $0.name == clip }, "\(clip) has no definition")
        }
    }

    @Test("unused clips are not reported as missing art")
    func loadableIsNotAll() {
        // Nagging about art for a feature that does not exist yet is noise.
        #expect(ClipName.all.contains(ClipName.sitting) == false)
        // Settings only reports art the app can actually draw. Sleep left the
        // list when winding down became two yawns and a walk-off; yawn joined
        // it, because it is now the whole late-night behaviour.
        #expect(ClipName.all.contains(ClipName.sleep) == false)
        #expect(ClipName.all.contains(ClipName.yawn))
        // Both are still readable, so a pack shipping them is not rejected.
        #expect(ClipName.loadable.contains(ClipName.sleep))
        #expect(ClipName.loadable.contains(ClipName.sitting))
        #expect(ClipName.loadable.contains(ClipName.sitting))
    }
}

@Suite("Peek placement")
struct PeekPlacementTests {

    private let visible = GRect(x: 0, y: 70, width: 1440, height: 805)

    // The real panel, not the canvas. The earlier version of this suite passed
    // the pack's 466pt canvas width as the window size, which quietly assumed
    // the artwork was exactly as wide as its window -- and that assumption was
    // the bug. With a 200pt character the app's panel is 240pt wide (the
    // minimum, so a bubble is not squeezed into a column) around a 198pt
    // drawing, leaving a 21pt gutter she used to sit behind.
    private let size = GSize(width: 240, height: 467)
    private let inset = 21.7
    private let artWidth = 53.0

    @Test("her first visible pixel lands on the screen edge, not the panel's")
    func firstPixelIsFlush() {
        let peek = CharacterPlacement.peekOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, artInset: inset
        )
        #expect(abs((peek.x + inset) - visible.minX) < 0.01)
        // Without the inset she hung 21pt inside the edge -- hovering, not peeking.
        let unfixed = CharacterPlacement.peekOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible
        )
        #expect(unfixed.x + inset > visible.minX)
    }

    @Test("the same holds at the right-hand edge")
    func firstPixelIsFlushOnTheRight() {
        let peek = CharacterPlacement.peekOrigin(
            corner: .bottomRight, size: size, visibleFrame: visible, artInset: inset
        )
        // Mirrored, so her leading pixel is measured from the panel's right.
        #expect(abs((peek.x + size.width - inset) - visible.maxX) < 0.01)
    }

    @Test("the inset scales with the character, so no constant could fix it")
    func insetDependsOnSize() {
        // 128pt character: a 203pt frame inside the same 240pt minimum panel.
        let small = CompanionLayout.edgeArtInset(
            panelWidth: 240, frameHeight: 203, canvasAspectRatio: 466.0 / 744, leadingFraction: 2.0 / 466
        )
        // 200pt character: a 317pt frame, so a much narrower gutter.
        let large = CompanionLayout.edgeArtInset(
            panelWidth: 240, frameHeight: 317, canvasAspectRatio: 466.0 / 744, leadingFraction: 2.0 / 466
        )
        #expect(small > 50)
        #expect(large < 25)
        #expect(small > large)
    }

    @Test("she starts the slide entirely off screen")
    func entryIsFullyHidden() {
        let entry = CharacterPlacement.peekEntryOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible,
            artInset: inset, artWidth: artWidth
        )
        // Her trailing pixel is at entry.x + inset + artWidth; all of it must be
        // past the edge. The old fixed 46pt slide left 54% of her showing.
        #expect(entry.x + inset + artWidth <= visible.minX + 0.01)
    }

    @Test("a peek from the right slides out to the right")
    func slideDirectionMirrors() {
        let resting = CharacterPlacement.peekOrigin(
            corner: .topRight, size: size, visibleFrame: visible, artInset: inset
        )
        let entry = CharacterPlacement.peekEntryOrigin(
            corner: .topRight, size: size, visibleFrame: visible,
            artInset: inset, artWidth: artWidth, screenFrame: nil
        )
        #expect(entry.x == resting.x + artWidth)
    }

    @Test("a peek is still a short lean, not a walk across the desktop")
    func shortSlide() {
        let resting = CharacterPlacement.peekOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, artInset: inset
        )
        let entry = CharacterPlacement.peekEntryOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible,
            artInset: inset, artWidth: artWidth
        )
        #expect(entry.y == resting.y)
        let walkEntry = CharacterPlacement.entryOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: 24
        )
        #expect(abs(entry.x - resting.x) < abs(walkEntry.x - resting.x))
    }

    @Test("an unmeasurable pack falls back to aligning the panel")
    func withoutMeasurementsNothingMoves() {
        // A pack whose art could not be read gets no inset, which is the old
        // behaviour -- imperfect, but never worse than it was.
        let peek = CharacterPlacement.peekOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, artInset: 0
        )
        #expect(peek.x == visible.minX)
    }

    @Test("a peek is bounded — she does not linger")
    func peekIsBrief() {
        // An unprompted peek that outstays its welcome is just an interruption.
        #expect(AiTwinConfiguration.production.chatterDuration > 0)
        #expect(AiTwinConfiguration.production.chatterDuration <= 6)
    }

    @Test("top corners peek at the top of the screen")
    func verticalFollowsCorner() {
        let bottom = CharacterPlacement.peekOrigin(corner: .bottomLeft, size: size, visibleFrame: visible)
        let top = CharacterPlacement.peekOrigin(corner: .topLeft, size: size, visibleFrame: visible)
        #expect(bottom.y < top.y)
        #expect(top.y + size.height <= visible.maxY)
    }
}

@Suite("Entrance choice per moment")
struct EntranceChoiceTests {

    @Test("reminders walk in; everything else appears")
    func entrancePolicy() {
        // Walking is reserved for "I have come over to tell you something".
        // A greeting, a cheer or an unprompted line are spontaneous, and walking
        // the full width of the screen for them reads as laboured.
        #expect(SummonPurpose.reminder(.water).entrance == .walk)
        #expect(SummonPurpose.reminder(.eyeBreak).entrance == .walk)
        #expect(SummonPurpose.reminder(.stretch).entrance == .walk)

        #expect(SummonPurpose.greeting.entrance == .pop)
        #expect(SummonPurpose.celebration.entrance == .pop)
        #expect(SummonPurpose.focus.entrance == .pop)
        // Chatter is the one that neither walks nor pops: she leans in from
        // off the edge, already talking.
        #expect(SummonPurpose.chatter.entrance == .slide)
        #expect(SummonPurpose.preview(ClipName.yawn).entrance == .pop)
    }

    @Test("every summon reason maps to a state without walking twice")
    func allPurposesReachAState() {
        let purposes: [SummonPurpose] = [
            .greeting, .celebration, .chatter, .focus,
            .preview(ClipName.cheer), .reminder(.water), .reminder(.stretch),
        ]
        for purpose in purposes {
            let machine = CharacterStateMachine()
            machine.handle(.summon(purpose))
            #expect(machine.state != .hidden, "\(purpose) did not summon anything")
            machine.handle(.arrivedAtCorner)
            #expect(machine.state != .hidden)
            // Arriving must never leave her mid-walk.
            #expect(machine.state.isWalking == false, "\(purpose) still walking after arrival")
        }
    }
}

@Suite("Moods: concern and sleepiness")
struct MoodMonitorTests {

    private let calendar = Calendar.testUTC
    private var noon: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
            .addingTimeInterval(12 * 3600)
    }
    private func at(hour: Int) -> Date {
        calendar.startOfDay(for: noon).addingTimeInterval(TimeInterval(hour * 3600))
    }

    @Test("a fresh monitor has nothing to say")
    func startsQuiet() {
        let monitor = MoodMonitor()
        #expect(monitor.mood(at: noon, conditions: .init(), calendar: calendar) == nil)
    }

    @Test("waving several reminders away earns a check-in")
    func skipsTriggerConcern() {
        var monitor = MoodMonitor()
        for _ in 0..<(MoodMonitor.Thresholds.default.skipsBeforeConcern - 1) { monitor.noteSkipped() }
        #expect(monitor.mood(at: noon, conditions: .init(), calendar: calendar) == nil)
        monitor.noteSkipped()
        #expect(monitor.mood(at: noon, conditions: .init(), calendar: calendar) == .concerned)
    }

    @Test("accepting a reminder clears the slate")
    func acceptingResets() {
        var monitor = MoodMonitor()
        for _ in 0..<5 { monitor.noteSkipped() }
        monitor.noteAccepted(at: noon)
        #expect(monitor.consecutiveSkips == 0)
        #expect(monitor.mood(at: noon, conditions: .init(), calendar: calendar) == nil)
    }

    @Test("a long unbroken stretch earns a check-in")
    func longWorkTriggersConcern() {
        var monitor = MoodMonitor()
        monitor.noteActive(at: noon)
        let justBefore = noon.addingTimeInterval(MoodMonitor.Thresholds.default.workBeforeConcern - 60)
        #expect(monitor.mood(at: justBefore, conditions: .init(), calendar: calendar) == nil)
        let after = noon.addingTimeInterval(MoodMonitor.Thresholds.default.workBeforeConcern + 60)
        #expect(monitor.mood(at: after, conditions: .init(), calendar: calendar) == .concerned)
    }

    @Test("stepping away restarts the stretch")
    func awayResetsWork() {
        var monitor = MoodMonitor()
        monitor.noteActive(at: noon)
        monitor.noteAway()
        #expect(monitor.continuousWork(at: noon.addingTimeInterval(5 * 3600)) == 0)
    }

    @Test("late at night she looks sleepy")
    func lateNightSleepy() {
        var monitor = MoodMonitor()
        monitor.noteActive(at: at(hour: 23))
        #expect(monitor.mood(at: at(hour: 22), conditions: .init(), calendar: calendar) == .sleepy)
        #expect(monitor.mood(at: at(hour: 23), conditions: .init(), calendar: calendar) == .sleepy)
        #expect(monitor.mood(at: at(hour: 2), conditions: .init(), calendar: calendar) == .sleepy)
    }

    @Test("a very long session makes her sleepy whatever the clock says")
    func longSessionSleepy() {
        var monitor = MoodMonitor()
        monitor.noteActive(at: noon)
        let after = noon.addingTimeInterval(MoodMonitor.Thresholds.default.workBeforeSleepy + 60)
        #expect(monitor.mood(at: after, conditions: .init(), calendar: calendar) == .sleepy)
    }

    @Test("sleepiness outranks concern")
    func sleepyWins() {
        // At 1am after six hours, "you should sleep" is the more useful line.
        var monitor = MoodMonitor()
        monitor.noteActive(at: at(hour: 1))
        for _ in 0..<5 { monitor.noteSkipped() }
        #expect(monitor.mood(at: at(hour: 1), conditions: .init(), calendar: calendar) == .sleepy)
    }

    @Test("a mood will not repeat until the cooldown has passed")
    func cooldown() {
        var monitor = MoodMonitor()
        for _ in 0..<MoodMonitor.Thresholds.default.skipsBeforeConcern { monitor.noteSkipped() }
        #expect(monitor.mood(at: noon, conditions: .init(), calendar: calendar) == .concerned)
        monitor.noteMoodShown(.concerned, at: noon)

        for _ in 0..<MoodMonitor.Thresholds.default.skipsBeforeConcern { monitor.noteSkipped() }
        let tooSoon = noon.addingTimeInterval(MoodMonitor.concernCooldown - 60)
        #expect(monitor.mood(at: tooSoon, conditions: .init(), calendar: calendar) == nil)
        let later = noon.addingTimeInterval(MoodMonitor.concernCooldown + 60)
        #expect(monitor.mood(at: later, conditions: .init(), calendar: calendar) == .concerned)
    }

    @Test("showing concern stops it asking again straight away")
    func showingConcernClearsSkips() {
        var monitor = MoodMonitor()
        for _ in 0..<MoodMonitor.Thresholds.default.skipsBeforeConcern { monitor.noteSkipped() }
        monitor.noteMoodShown(.concerned, at: noon)
        #expect(monitor.consecutiveSkips == 0)
    }

    @Test("every condition can veto a mood on its own")
    func conditionsVeto() {
        var monitor = MoodMonitor()
        for _ in 0..<MoodMonitor.Thresholds.default.skipsBeforeConcern { monitor.noteSkipped() }
        #expect(monitor.mood(at: noon, conditions: .init(isPaused: true), calendar: calendar) == nil)
        #expect(monitor.mood(at: noon, conditions: .init(inQuietHours: true), calendar: calendar) == nil)
        #expect(monitor.mood(at: noon, conditions: .init(isFocusing: true), calendar: calendar) == nil)
        #expect(monitor.mood(at: noon, conditions: .init(characterIsBusy: true), calendar: calendar) == nil)
        #expect(monitor.mood(at: noon, conditions: .init(idleSeconds: 10 * 60), calendar: calendar) == nil)
    }

    @Test("moods map to the right artwork")
    func moodClips() {
        #expect(MoodMonitor.Mood.concerned.clipName == ClipName.concerned)
        #expect(MoodMonitor.Mood.sleepy.clipName == ClipName.yawn)
    }

    @Test("concern walks over; sleepiness just appears")
    func moodEntrances() {
        // Concern is an errand -- she comes to say it. Being tired is not.
        #expect(SummonPurpose.mood(.concerned).entrance == .walk)
        #expect(SummonPurpose.mood(.sleepy).entrance == .pop)
    }

    @Test("a sleepy yawn can settle into sleep")
    func yawnBecomesSleep() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.mood(.sleepy)))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .feeling(.sleepy))
        #expect(machine.state.clipName == ClipName.yawn)
        machine.handle(.fellAsleep)
        #expect(machine.state == .sleeping)
        #expect(machine.state.clipName == ClipName.sleep)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("a yawn outside the night window just leaves")
    func yawnLeavesByDay() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.mood(.sleepy)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("concern walks in and then leaves")
    func concernFlow() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.mood(.concerned)))
        #expect(machine.state == .entering(.mood(.concerned)))
        #expect(machine.state.isWalking)
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .feeling(.concerned))
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("a reminder wakes her from sleep")
    func reminderWakesHer() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.mood(.sleepy)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.fellAsleep)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }

    @Test("sleep nudges repeat through the night rather than once")
    func sleepyRepeats() {
        var monitor = MoodMonitor()
        let night = at(hour: 23)
        #expect(monitor.mood(at: night, conditions: .init(), calendar: calendar) == .sleepy)
        monitor.noteMoodShown(.sleepy, at: night)

        let tooSoon = night.addingTimeInterval(MoodMonitor.Thresholds.default.sleepyRepeat - 60)
        #expect(monitor.mood(at: tooSoon, conditions: .init(), calendar: calendar) == nil)
        let later = night.addingTimeInterval(MoodMonitor.Thresholds.default.sleepyRepeat + 60)
        #expect(monitor.mood(at: later, conditions: .init(), calendar: calendar) == .sleepy)
    }

    @Test("night never turns into a stream of alternating moods")
    func nightStaysSleepy() {
        // Once she has just nudged about sleep, she must not immediately switch
        // to concern instead -- that would fill the night with interruptions.
        var monitor = MoodMonitor()
        for _ in 0..<9 { monitor.noteSkipped() }
        let night = at(hour: 23)
        monitor.noteMoodShown(.sleepy, at: night)
        #expect(monitor.mood(at: night.addingTimeInterval(60), conditions: .init(), calendar: calendar) == nil)
    }

    @Test("thresholds are configurable and clamped to something sane")
    func thresholdsConfigurable() {
        var settings = AiTwinSettings.defaults
        #expect(settings.moodsEnabled)
        #expect(settings.moodThresholds.workBeforeConcern == 3 * 3600)
        #expect(settings.moodThresholds.nightStartMinutes == 22 * 60)

        settings.moodThresholds = MoodMonitor.Thresholds(
            skipsBeforeConcern: 0, workBeforeConcern: 1, nightStartMinutes: 9999, sleepyRepeat: 0
        )
        #expect(settings.moodThresholds.skipsBeforeConcern >= 1)
        #expect(settings.moodThresholds.nightStartMinutes <= 1439)
        #expect(settings.moodThresholds.sleepyRepeat >= 60)
    }

    @Test("a custom concern threshold is honoured")
    func customConcernThreshold() {
        var monitor = MoodMonitor(thresholds: .init(workBeforeConcern: 1 * 3600))
        monitor.noteActive(at: noon)
        #expect(monitor.mood(at: noon.addingTimeInterval(3000), conditions: .init(), calendar: calendar) == nil)
        #expect(monitor.mood(at: noon.addingTimeInterval(3700), conditions: .init(), calendar: calendar) == .concerned)
    }

    @Test("moods can be switched off entirely")
    func moodsCanBeDisabled() {
        var settings = AiTwinSettings.defaults
        settings.moodsEnabled = false
        #expect(settings.moodsEnabled == false)
    }

    @Test("a reminder interrupts a mood")
    func reminderBeatsMood() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.mood(.concerned)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }
}

@Suite("Character scales by character, not canvas")
struct PackScalingTests {

    private func clip() -> AnimationClip {
        AnimationClip(name: ClipName.idle, framePaths: ["idle_1.png"], frameDuration: 0.125, loops: true)
    }

    @Test("a pack with no manifest fills its frame, as before")
    func legacyPackUnchanged() {
        let pack = CharacterPack(name: "Old", clips: [ClipName.idle: clip()])
        #expect(pack.characterHeightFraction == 1)
        #expect(pack.frameHeight(forCharacterHeight: 192) == 192)
    }

    @Test("headroom for tall poses does not shrink the character")
    func headroomDoesNotShrink() {
        // The bug: growing the canvas to fit a jump made her render 15% smaller
        // in every clip, because the app scaled frames by canvas height.
        let pack = CharacterPack(name: "Nish", clips: [ClipName.idle: clip()],
                                 characterHeightFraction: 470.0 / 604.0)
        let frame = pack.frameHeight(forCharacterHeight: 192)
        #expect(frame > 192)
        // The character within that frame is exactly the requested height.
        #expect(abs(frame * pack.characterHeightFraction - 192) < 0.001)
    }

    @Test("the panel grows with the frame so nothing is cropped")
    func panelFollowsFrame() {
        let plain = CompanionLayout.panelSize(characterHeight: 192)
        let padded = CompanionLayout.panelSize(characterHeight: 192, frameHeight: 247)
        #expect(padded.height > plain.height)
        #expect(padded.height == 247 + CompanionLayout.bubbleReservedHeight)
    }

    @Test("an absurd fraction is clamped rather than exploding the window")
    func fractionClamped() {
        #expect(CharacterPack(name: "x", clips: [:], characterHeightFraction: 0).characterHeightFraction == 0.1)
        #expect(CharacterPack(name: "x", clips: [:], characterHeightFraction: 9).characterHeightFraction == 1)
    }
}

@Suite("Cloud sits above the current pose")
struct BubblePlacementTests {

    private func clip(_ name: String, top: Double) -> AnimationClip {
        AnimationClip(name: name, framePaths: ["\(name)_1.png"],
                      frameDuration: 0.125, loops: true, contentTopFraction: top)
    }

    @Test("a standing pose puts the cloud near her head, not near the ceiling")
    func standingIsSnug() {
        // The bug: anchoring to the frame left a 50pt gap, because the frame
        // carries headroom only a jump ever uses.
        let idle = clip(ClipName.idle, top: 0.1937)
        let head = idle.headHeight(inFrameOf: 247)
        #expect(head > 190 && head < 205)
        #expect(head < 247)
    }

    @Test("a jump lifts the cloud clear of her hands")
    func jumpLiftsCloud() {
        let cheer = clip(ClipName.cheer, top: 0)
        #expect(cheer.headHeight(inFrameOf: 247) == 247)
        let idle = clip(ClipName.idle, top: 0.1937)
        #expect(cheer.headHeight(inFrameOf: 247) > idle.headHeight(inFrameOf: 247))
    }

    @Test("sitting brings the cloud down with her")
    func sittingLowersCloud() {
        let sitting = clip(ClipName.sitting, top: 0.303)
        let idle = clip(ClipName.idle, top: 0.1937)
        #expect(sitting.headHeight(inFrameOf: 247) < idle.headHeight(inFrameOf: 247))
    }

    @Test("a clip with no manifest data clears the whole frame")
    func legacyClearsEverything() {
        #expect(clip(ClipName.idle, top: 0).headHeight(inFrameOf: 247) == 247)
    }

    @Test("an absurd fraction cannot push the cloud through her")
    func fractionClamped() {
        #expect(clip("x", top: -1).contentTopFraction == 0)
        #expect(clip("x", top: 5).contentTopFraction == 0.9)
    }
}

@Suite("Clip sequences")
struct ClipSequenceTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a routine plays its beats in order")
    func playsInOrder() {
        let routine = ClipSequence(name: "t", steps: [
            ClipStep("a", duration: 1), ClipStep("b", duration: 1), ClipStep("c", duration: 1),
        ])
        let player = SequencePlayer()
        player.start(routine, at: start)
        #expect(player.currentClip == "a")

        #expect(player.tick(at: start.addingTimeInterval(1)))
        #expect(player.currentClip == "b")
        #expect(player.tick(at: start.addingTimeInterval(2)))
        #expect(player.currentClip == "c")
    }

    @Test("a beat holds for its full duration")
    func beatHolds() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [
            ClipStep("a", duration: 2), ClipStep("b", duration: 1),
        ]), at: start)
        #expect(player.tick(at: start.addingTimeInterval(1.9)) == false)
        #expect(player.currentClip == "a")
        #expect(player.tick(at: start.addingTimeInterval(2.0)))
        #expect(player.currentClip == "b")
    }

    @Test("a routine finishes after its last beat")
    func finishes() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [ClipStep("a", duration: 1)]), at: start)
        #expect(player.isFinished == false)
        player.tick(at: start.addingTimeInterval(1))
        #expect(player.isFinished)
    }

    @Test("an indefinite beat waits for the outside world")
    func indefiniteBeatWaits() {
        // Concern holds until you answer her; no amount of time moves it on.
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [
            ClipStep("a", holdsIndefinitely: true), ClipStep("b", duration: 1),
        ]), at: start)
        #expect(player.isHolding)
        #expect(player.tick(at: start.addingTimeInterval(3600)) == false)
        #expect(player.currentClip == "a")

        #expect(player.release(at: start.addingTimeInterval(10)))
        #expect(player.currentClip == "b")
    }

    @Test("releasing the last beat finishes the routine")
    func releaseAtEnd() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [ClipStep("a", holdsIndefinitely: true)]), at: start)
        #expect(player.release(at: start) == false)
        #expect(player.isFinished)
    }

    @Test("releasing a timed beat does nothing")
    func releaseIgnoredOnTimedBeat() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [ClipStep("a", duration: 1), ClipStep("b")]), at: start)
        #expect(player.release(at: start) == false)
        #expect(player.currentClip == "a")
    }

    @Test("a beat can wait on the animation instead of the clock")
    func waitsForClip() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "t", steps: [
            ClipStep("a", holdsUntilFinished: true), ClipStep("b", duration: 1),
        ]), at: start)
        #expect(player.tick(at: start.addingTimeInterval(99), clipFinished: false) == false)
        #expect(player.tick(at: start.addingTimeInterval(99), clipFinished: true))
        #expect(player.currentClip == "b")
    }

    @Test("an empty routine is finished immediately rather than hanging")
    func emptyRoutine() {
        let player = SequencePlayer()
        player.start(ClipSequence(name: "empty", steps: []), at: start)
        #expect(player.isFinished)
        #expect(player.currentClip == nil)
        #expect(player.tick(at: start.addingTimeInterval(10)) == false)
    }

    @Test("stopping clears everything")
    func stop() {
        let player = SequencePlayer()
        player.start(.stretchRoutine, at: start)
        player.stop()
        #expect(player.currentClip == nil)
        #expect(player.isFinished)
    }

    // MARK: The catalogue

    @Test("stretching shows the stretch, without a detour")
    func stretchIsDirect() {
        // She has walked over to say it, so sitting down to demonstrate first
        // reads as a detour and delays the message.
        let routine = ClipSequence.stretchRoutine
        #expect(routine.clips.first == ClipName.stretch)
        #expect(routine.clips.contains(ClipName.sitting) == false)
    }

    @Test("finishing a focus session goes straight from the chair to the cheer")
    func focusFinishGetsUp() {
        let routine = ClipSequence.focusFinishedRoutine
        #expect(routine.clips == [ClipName.focus, ClipName.cheer])
        // The idle beat in between is deliberately gone: a pause between
        // looking up and celebrating read as hesitation, not as standing up.
        #expect(routine.clips.contains(ClipName.idle) == false)
    }

    @Test("winding down is two yawns and then she leaves")
    func sleepRoutineYawnsTwice() {
        let routine = ClipSequence.sleepRoutine
        #expect(routine.clips == [ClipName.yawn, ClipName.yawn])
        // Nothing holds any more. She used to settle into the sleep pose and
        // stay parked on the desktop until something woke her, which stopped
        // reading as a nudge to stop working and started reading as clutter.
        #expect(routine.steps.allSatisfy { $0.holdsIndefinitely == false })
        #expect(routine.clips.contains(ClipName.sleep) == false)
        #expect(routine.duration > 0)
    }

    @Test("a milestone is the cheer alone")
    func milestoneIsBigger() {
        #expect(ClipSequence.milestoneRoutine.clips == [ClipName.cheer])
        #expect(ClipSequence.milestoneRoutine.duration > ClipSequence.waterLoggedRoutine.duration)
        // No happy beat first: the everyday jump before the big one made the
        // milestone read as two celebrations bolted together.
        #expect(ClipSequence.milestoneRoutine.clips.contains(ClipName.happy) == false)
        #expect(ClipSequence.waterLoggedRoutine.clips == [ClipName.happy])
    }

    @Test("every routine is reachable by name and uses real clips")
    func catalogueIsSound() {
        for routine in ClipSequence.all {
            #expect(ClipSequence.named(routine.name) == routine)
            #expect(!routine.steps.isEmpty, "\(routine.name) is empty")
            for clip in routine.clips {
                #expect(ClipName.loadable.contains(clip), "\(routine.name) uses unknown clip \(clip)")
            }
        }
    }

    @Test("an unknown routine name resolves to nothing rather than crashing")
    func unknownName() {
        #expect(ClipSequence.named("nope") == nil)
    }

    @Test("a routine can be previewed end to end")
    func sequencePreviewState() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.previewSequence("stretch")))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .previewingSequence(name: "stretch"))
        #expect(machine.state.clipName == ClipName.stretch)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("previewing another routine swaps straight over")
    func sequencePreviewSwaps() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.previewSequence("stretch")))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.previewSequence("sleep")))
        #expect(machine.state == .previewingSequence(name: "sleep"))
    }
}

@Suite("Code review regressions")
struct ReviewRegressionTests {

    private let calendar = Calendar.testUTC
    private var day0: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: day0)! }

    @Test("a streak message carries the real day count")
    func streakMessageHasDays() {
        // It used to read "0-day streak": pick already expanded the template,
        // so the second fill had nothing left to replace.
        let catalog = MessageCatalog(randomSource: { 0 })
        for _ in 0..<MessageCatalog.streakMessages.count {
            let line = catalog.nextStreakMessage(days: 7, name: "Suresh")
            #expect(!line.contains("{"))
            #expect(!line.contains("0 day"), "lost the count: \(line)")
            if line.contains("7") || !MessageCatalog.streakMessages.contains(where: { $0.contains("{days}") }) {
                continue
            }
            Issue.record("day count missing from: \(line)")
        }
    }

    @Test("every day-count template renders the number it was given")
    func everyStreakTemplateRenders() {
        for template in MessageCatalog.streakMessages where template.contains("{days}") {
            #expect(MessageCatalog.fill(template, name: "Suresh", days: 30).contains("30"))
        }
    }

    @Test("a focus break can get her out of the chair")
    func focusBreakCanInterrupt() {
        // Without this the session's own break never played, and reminders
        // released at the break were sent to a state that ignored them.
        let machine = CharacterStateMachine()
        machine.handle(.summon(.focus))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .focusing)
        machine.handle(.summon(.celebration))
        #expect(machine.state == .celebrating)
    }

    @Test("a reminder reaches her mid-session rather than timing out unseen")
    func reminderReachesFocus() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.focus))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }

    @Test("starting a focus session while she is on screen sits her down")
    func focusReachableFromOnScreen() {
        // It used to run entirely invisibly from any visible state.
        for start: CharacterEvent in [.summon(.greeting), .summon(.chatter), .summon(.mood(.sleepy))] {
            let machine = CharacterStateMachine()
            machine.handle(start)
            machine.handle(.arrivedAtCorner)
            machine.handle(.summon(.focus))
            #expect(machine.state == .focusing, "focus unreachable from \(start)")
        }
    }

    @Test("focus still ignores a rest timer")
    func focusIgnoresTimers() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.focus))
        machine.handle(.arrivedAtCorner)
        machine.handle(.restTimeout)
        #expect(machine.state == .focusing)
    }

    @Test("raising the goal on another machine cannot break an earned streak")
    func mergeKeepsCompletedDays() {
        // Taking max(waterGoal) used to retroactively un-meet a finished day.
        var here = ActivityLog()
        for _ in 0..<8 { here.apply(.glassLogged(goal: 8), at: day(0), calendar: calendar) }
        #expect(here.record(on: day(0), calendar: calendar)?.metWaterGoal == true)

        var elsewhere = ActivityLog()
        elsewhere.apply(.glassLogged(goal: 12), at: day(0), calendar: calendar)

        let merged = here.merged(with: elsewhere)
        #expect(merged.record(on: day(0), calendar: calendar)?.metWaterGoal == true,
                "a completed day was un-met by the merge")
    }

    @Test("merging still takes the goal from the fuller record")
    func mergeUsesFullerRecordsGoal() {
        var sparse = ActivityLog()
        sparse.apply(.glassLogged(goal: 3), at: day(0), calendar: calendar)
        var full = ActivityLog()
        for _ in 0..<6 { full.apply(.glassLogged(goal: 6), at: day(0), calendar: calendar) }
        #expect(sparse.merged(with: full).record(on: day(0), calendar: calendar)?.waterGoal == 6)
    }
}

@Suite("History export")
struct HistoryExportTests {

    private let calendar = Calendar.testUTC
    private var day0: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }

    private func sample() -> ActivityLog {
        var log = ActivityLog()
        for _ in 0..<4 { log.apply(.glassLogged(goal: 12), at: day0, calendar: calendar) }
        log.apply(.reminderAccepted(.eyeBreak), at: day0, calendar: calendar)
        log.apply(.reminderSnoozed(.eyeBreak), at: day0, calendar: calendar)
        log.apply(.focusSessionCompleted(minutes: 25), at: day0, calendar: calendar)
        return log
    }

    @Test("the export has a header and one row per recorded day")
    func shape() {
        let csv = sample().csv(intake: .default, calendar: calendar)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("date,water_ml,goal_ml"))
    }

    @Test("volumes are exported in millilitres, not glasses")
    func exportsMillilitres() {
        // Glasses would be meaningless the moment the glass size changes.
        let csv = sample().csv(intake: WaterIntake(glassSize: 250, dailyGoal: 3000), calendar: calendar)
        let row = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(row[1] == "1000")     // 4 glasses x 250ml
        #expect(row[2] == "3000")
        #expect(row[3] == "no")       // 1L of a 3L goal
    }

    @Test("a met goal is marked as met")
    func marksMetGoal() {
        var log = ActivityLog()
        for _ in 0..<12 { log.apply(.glassLogged(goal: 12), at: day0, calendar: calendar) }
        let row = log.csv(intake: WaterIntake(glassSize: 250, dailyGoal: 3000), calendar: calendar)
            .split(separator: "\n")[1]
        #expect(row.contains(",yes,"))
    }

    @Test("break outcomes and focus time survive the round trip")
    func carriesEveryColumn() {
        let row = sample().csv(intake: .default, calendar: calendar).split(separator: "\n")[1]
        let fields = row.split(separator: ",", omittingEmptySubsequences: false)
        #expect(fields.count == 13)
        #expect(fields[5] == "1")      // eye breaks taken
        #expect(fields[6] == "1")      // snoozed
        #expect(fields[12] == "25")    // focus minutes
    }

    @Test("an empty history exports a header and nothing else")
    func emptyExport() {
        let csv = ActivityLog().csv(intake: .default, calendar: calendar)
        #expect(csv.split(separator: "\n").count == 1)
    }

    @Test("the filename sorts chronologically")
    func filename() {
        let name = ActivityLog.exportFilename(on: day0, calendar: calendar)
        #expect(name.hasPrefix("AiTwin-history-"))
        #expect(name.hasSuffix(".csv"))
    }

    @Test("a peek hugs the true screen edge, not the Dock-inset area")
    func peekUsesFullScreenEdge() {
        // With a Dock on the left, the visible frame starts well inside the
        // display; leaning in from there reads as hovering, not peeking.
        let visible = GRect(x: 80, y: 70, width: 1360, height: 805)
        let full = GRect(x: 0, y: 0, width: 1440, height: 900)
        let size = GSize(width: 466, height: 744)
        let peek = CharacterPlacement.peekOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, screenFrame: full
        )
        #expect(peek.x == 0)
        // Vertically she still avoids the Dock and the menu bar.
        #expect(peek.y >= visible.minY)
    }
}

@Suite("Pack layout")
struct PackGeometryTests {

    /// A frame with content occupying a given box on a 1000x1000 image.
    private func frame(top: Int, bottom: Int, left: Int = 400, right: Int = 600) -> FrameBounds {
        FrameBounds(width: 1000, height: 1000, left: left, top: top, right: right, bottom: bottom)
    }

    @Test("standing clips all end up the same height")
    func standingClipsMatch() {
        // Different generation zooms in, one consistent character out.
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 100, bottom: 800)],   // 700 tall
            ClipName.walk: [frame(top: 50, bottom: 950)],    // 900 tall
            ClipName.wave: [frame(top: 200, bottom: 700)],   // 500 tall
        ])
        let heights = [ClipName.idle, ClipName.walk, ClipName.wave].compactMap { clip -> Double? in
            guard let p = layout.placements[clip] else { return nil }
            let source: Double = clip == ClipName.idle ? 700 : (clip == ClipName.walk ? 900 : 500)
            return source * p.scale
        }
        #expect(heights.count == 3)
        for height in heights { #expect(abs(height - 470) < 1) }
    }

    @Test("every clip stands on the same floor")
    func sharedBaseline() {
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 100, bottom: 800)],
            ClipName.wave: [frame(top: 200, bottom: 700)],
        ])
        for clip in [ClipName.idle, ClipName.wave] {
            guard let p = layout.placements[clip] else { continue }
            let bottom = clip == ClipName.idle ? 800.0 : 700.0
            let feetOnCanvas = Double(p.offsetY) + bottom * p.scale
            #expect(abs(feetOnCanvas - Double(layout.baseline)) < 1.5)
        }
    }

    @Test("one scale per clip, so motion inside a clip survives")
    func oneScalePerClip() {
        // Scaling frames individually would flatten a walk's bob.
        let layout = PackGeometry.layout(for: [
            ClipName.walk: [frame(top: 100, bottom: 800), frame(top: 110, bottom: 800),
                            frame(top: 100, bottom: 790)],
        ])
        #expect(layout.placements[ClipName.walk] != nil)
        #expect(layout.placements.count == 1)
    }

    @Test("a jump is not cropped, because the canvas allows for its reach")
    func jumpFitsOnCanvas() {
        // This is the bug that cut off her raised arms: a clip is aligned by its
        // lowest point, so a jump sits higher than its own height suggests.
        let layout = PackGeometry.layout(for: [
            ClipName.cheer: [
                frame(top: 200, bottom: 900),   // standing
                frame(top: 20, bottom: 650),    // mid-jump, feet off the ground
            ],
        ])
        let p = layout.placements[ClipName.cheer]!
        let topOnCanvas = Double(p.offsetY) + 20 * p.scale
        #expect(topOnCanvas >= 0, "the jump would be cropped at the top")
        let feet = Double(p.offsetY) + 900 * p.scale
        #expect(feet <= Double(layout.canvasHeight))
    }

    @Test("a clip that cannot fit is scaled down, never cropped")
    func shrinksRatherThanCrops() {
        // Losing a few percent of size beats losing her hands.
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 400, bottom: 500)],       // small, sets the scale high
            ClipName.cheer: [frame(top: 0, bottom: 1000)],       // enormous reach
        ])
        let p = layout.placements[ClipName.cheer]!
        #expect(Double(p.offsetY) + 0 * p.scale >= -0.5)
        #expect(Double(p.offsetY) + 1000 * p.scale <= Double(layout.canvasHeight) + 0.5)
    }

    @Test("seated poses are shorter than standing ones")
    func seatedIsShorter() {
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 100, bottom: 800)],
            ClipName.focus: [frame(top: 100, bottom: 800)],
        ])
        let idle = layout.placements[ClipName.idle]!.scale
        let focus = layout.placements[ClipName.focus]!.scale
        #expect(focus < idle, "a seated pose should not render as tall as standing")
    }

    @Test("the peeking pose hugs the canvas edge and sits at head height")
    func peekIsEdgeAligned() {
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 100, bottom: 800)],
            ClipName.peek: [frame(top: 100, bottom: 800, left: 300, right: 420)],
        ])
        let peek = layout.placements[ClipName.peek]!
        // Pinned to the left edge rather than centred.
        #expect(abs(Double(peek.offsetX) + 300 * peek.scale) < 1.5)
        // And not standing on the floor.
        let feet = Double(peek.offsetY) + 800 * peek.scale
        #expect(feet < Double(layout.baseline) - 10)
    }

    @Test("each clip reports where its art starts, for placing the cloud")
    func recordsClipTops() {
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [frame(top: 200, bottom: 900)],
            ClipName.cheer: [frame(top: 0, bottom: 700)],
        ])
        let idleTop = layout.clipTopFractions[ClipName.idle]!
        let cheerTop = layout.clipTopFractions[ClipName.cheer]!
        #expect(cheerTop < idleTop, "a jump reaches higher, so its art starts nearer the top")
        for value in layout.clipTopFractions.values { #expect(value >= 0 && value <= 0.9) }
    }

    @Test("empty input yields a usable layout rather than nothing")
    func emptyInput() {
        let layout = PackGeometry.layout(for: [:])
        #expect(layout.canvasHeight >= PackGeometry.minimumCanvasHeight)
        #expect(layout.placements.isEmpty)
    }

    @Test("blank frames are ignored rather than breaking the maths")
    func blankFramesIgnored() {
        let layout = PackGeometry.layout(for: [
            ClipName.idle: [FrameBounds(width: 100, height: 100, left: 0, top: 0, right: 0, bottom: 0),
                            frame(top: 100, bottom: 800)],
        ])
        #expect(layout.placements[ClipName.idle] != nil)
    }
}
