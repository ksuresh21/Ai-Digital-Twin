import Foundation
import Testing
@testable import AiTwinCore

@Suite("ReminderTimer")
struct ReminderTimerTests {

    @Test("a new timer is not running until started")
    func startsIdle() {
        let timer = ReminderTimer(kind: .water, interval: 60)
        #expect(timer.isRunning == false)
        #expect(timer.deadline == nil)
    }

    @Test("start schedules a deadline one interval away")
    func startSetsDeadline() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 60)
        timer.start(at: clock.now)
        #expect(timer.deadline == clock.now.addingTimeInterval(60))
        #expect(timer.isRunning)
    }

    @Test("does not fire before the interval elapses")
    func doesNotFireEarly() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .eyeBreak, interval: 40 * 60)
        timer.start(at: clock.now)

        clock.advance(40 * 60 - 1)
        #expect(timer.hasFired(at: clock.now) == false)
    }

    @Test("fires exactly at the configured interval")
    func firesAtInterval() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .eyeBreak, interval: 40 * 60)
        timer.start(at: clock.now)

        clock.advance(40 * 60)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("stays fired if nothing looks at it for a while")
    func staysFired() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 30)
        timer.start(at: clock.now)
        clock.advance(300)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("stop cancels the countdown")
    func stopCancels() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 30)
        timer.start(at: clock.now)
        timer.stop()

        clock.advance(600)
        #expect(timer.hasFired(at: clock.now) == false)
        #expect(timer.isRunning == false)
    }

    @Test("restarting gives a full fresh interval")
    func restart() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 60)
        timer.start(at: clock.now)
        clock.advance(59)
        timer.start(at: clock.now)

        clock.advance(59)
        #expect(timer.hasFired(at: clock.now) == false)
        clock.advance(1)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("pause preserves the time remaining")
    func pausePreservesRemaining() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .eyeBreak, interval: 100)
        timer.start(at: clock.now)

        clock.advance(30)
        timer.pause(at: clock.now)
        #expect(timer.remaining(at: clock.now) == 70)

        // An hour away from the keyboard must not consume the countdown.
        clock.advance(3600)
        #expect(timer.hasFired(at: clock.now) == false)
        #expect(timer.remaining(at: clock.now) == 70)
    }

    @Test("resume continues from where it paused")
    func resumeContinues() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .eyeBreak, interval: 100)
        timer.start(at: clock.now)
        clock.advance(30)
        timer.pause(at: clock.now)
        clock.advance(3600)
        timer.resume(at: clock.now)

        clock.advance(69)
        #expect(timer.hasFired(at: clock.now) == false)
        clock.advance(1)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("pausing twice does not lose the remaining time")
    func doublePauseIsSafe() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 100)
        timer.start(at: clock.now)
        clock.advance(40)
        timer.pause(at: clock.now)
        clock.advance(10)
        timer.pause(at: clock.now)
        #expect(timer.remaining(at: clock.now) == 60)
    }

    @Test("snooze pushes the deadline out by the snooze duration")
    func snooze() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 3600)
        timer.start(at: clock.now)
        clock.advance(3600)
        #expect(timer.hasFired(at: clock.now))

        timer.snooze(by: 300, at: clock.now)
        #expect(timer.hasFired(at: clock.now) == false)

        clock.advance(300)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("changing the interval on a running timer takes effect immediately")
    func setIntervalRestarts() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .eyeBreak, interval: 40 * 60)
        timer.start(at: clock.now)
        clock.advance(60)

        // Switching to Test Mode must not require waiting out the old interval.
        timer.setInterval(10, at: clock.now)
        clock.advance(10)
        #expect(timer.hasFired(at: clock.now))
    }

    @Test("changing the interval on a stopped timer does not start it")
    func setIntervalOnStoppedTimer() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 60)
        timer.setInterval(10, at: clock.now)

        clock.advance(100)
        #expect(timer.isRunning == false)
        #expect(timer.hasFired(at: clock.now) == false)
        #expect(timer.interval == 10)
    }

    @Test("a paused timer stays paused across an interval change")
    func setIntervalKeepsPause() {
        let clock = FakeClock()
        let timer = ReminderTimer(kind: .water, interval: 60)
        timer.start(at: clock.now)
        timer.pause(at: clock.now)

        timer.setInterval(10, at: clock.now)
        #expect(timer.isPaused)
        clock.advance(100)
        #expect(timer.hasFired(at: clock.now) == false)
    }
}
