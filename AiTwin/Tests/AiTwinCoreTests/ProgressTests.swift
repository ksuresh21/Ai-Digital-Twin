import Foundation
import Testing
@testable import AiTwinCore

/// The Progress tab's data: today's plain quantities, the by-hour breakdown,
/// and the monthly clear-out offer.
@Suite("Progress data")
struct ProgressDataTests {

    private let calendar = Calendar.testUTC
    /// Midday on 14 November 2023, so hour arithmetic is unambiguous.
    private var noon: Date { Date(timeIntervalSince1970: 1_699_963_200) }

    private func at(hour: Int, day: Int = 0) -> Date {
        let start = calendar.startOfDay(for: noon)
        return calendar.date(byAdding: .hour, value: hour,
                             to: calendar.date(byAdding: .day, value: day, to: start)!)!
    }

    // MARK: Timestamps

    @Test("logging a glass records when it happened, not just that it did")
    func glassIsTimestamped() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: at(hour: 14), calendar: calendar)
        #expect(log.events.count == 2)
        #expect(log.events.allSatisfy { $0.kind == .glass })
        #expect(calendar.component(.hour, from: log.events[0].at) == 9)
        #expect(calendar.component(.hour, from: log.events[1].at) == 14)
    }

    @Test("an accepted water reminder is not double-counted")
    func acceptedWaterIsNotItsOwnEvent() {
        // Logging the glass is the event. Recording the acceptance too would
        // show two drinks for one glass.
        var log = ActivityLog()
        log.apply(.reminderAccepted(.water), at: at(hour: 9), calendar: calendar)
        #expect(log.events.isEmpty)
    }

    @Test("breaks, stretches and focus are all timestamped")
    func otherEventsAreTimestamped() {
        var log = ActivityLog()
        log.apply(.reminderAccepted(.eyeBreak), at: at(hour: 10), calendar: calendar)
        log.apply(.reminderSnoozed(.stretch), at: at(hour: 11), calendar: calendar)
        log.apply(.reminderIgnored(.eyeBreak), at: at(hour: 12), calendar: calendar)
        log.apply(.focusSessionCompleted(minutes: 25), at: at(hour: 13), calendar: calendar)
        #expect(log.events.map(\.kind) == [.eyeBreakTaken, .stretchSnoozed, .eyeBreakMissed, .focusCompleted])
        #expect(log.events.last?.minutes == 25)
    }

    @Test("events are readable a day at a time")
    func eventsForOneDay() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9, day: -1), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: at(hour: 23), calendar: calendar)
        #expect(log.events(on: noon, calendar: calendar).count == 2)
    }

    @Test("a log stored before events existed still decodes")
    func oldLogsDecode() throws {
        // Real stored history has no `events` key. Failing to decode would
        // throw away someone's entire recorded past.
        let json = #"{"days":[{"dayStart":723081600,"glasses":3,"waterGoal":8,"eyeBreaksAccepted":0,"eyeBreaksSnoozed":0,"eyeBreaksIgnored":0,"stretchesAccepted":0,"stretchesSnoozed":0,"stretchesIgnored":0,"focusSessionsCompleted":0,"focusMinutes":0}]}"#
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(json.utf8))
        #expect(log.days.count == 1)
        #expect(log.days.first?.glasses == 3)
        #expect(log.events.isEmpty)
    }

    // MARK: Today

    @Test("today reads as plain quantities, in millilitres")
    func todaySummary() {
        let record = DailyRecord(
            dayStart: calendar.startOfDay(for: noon),
            glasses: 6, waterGoal: 12,
            eyeBreaksAccepted: 3, eyeBreaksSnoozed: 1, eyeBreaksIgnored: 2,
            stretchesAccepted: 2, stretchesSnoozed: 1, stretchesIgnored: 0,
            focusSessionsCompleted: 2, focusMinutes: 50
        )
        let day = DaySummary.from(record, intake: WaterIntake(glassSize: 250, dailyGoal: 3000))
        #expect(day.millilitres == 1500)
        #expect(day.goalMillilitres == 3000)
        #expect(day.metWaterGoal == false)
        #expect(day.waterProgress == 0.5)
        // The "how many did I skip" number: snoozed and missed, both kinds.
        #expect(day.skipped == 4)
        #expect(day.focusSessions == 2)
        #expect(day.didAnything)
    }

    @Test("water progress cannot overflow the bar")
    func waterProgressIsCapped() {
        let record = DailyRecord(dayStart: calendar.startOfDay(for: noon), glasses: 40, waterGoal: 12)
        let day = DaySummary.from(record, intake: WaterIntake(glassSize: 250, dailyGoal: 3000))
        #expect(day.waterProgress == 1)
        #expect(day.metWaterGoal)
    }

    @Test("an untouched day says so rather than charting zeroes")
    func emptyDay() {
        let day = DaySummary.from(DailyRecord(dayStart: noon), intake: .init())
        #expect(day.didAnything == false)
        #expect(day.skipped == 0)
    }

    // MARK: By hour

    @Test("today spreads across twenty-four hours whatever happened")
    func hourlyBucketsAlwaysSpanTheDay() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: at(hour: 17), calendar: calendar)
        let buckets = HourlyActivity.buckets(from: log.events(on: noon, calendar: calendar),
                                             calendar: calendar)
        // A stable x-axis: a quiet morning is a flat line, not a missing one.
        #expect(buckets.count == 24)
        #expect(buckets.map(\.hour) == Array(0..<24))
        #expect(buckets[9].count == 2)
        #expect(buckets[17].count == 1)
        #expect(buckets[0].count == 0)
        #expect(HourlyActivity.busiestHour(buckets)?.hour == 9)
    }

    @Test("the by-hour view can be filtered to one activity")
    func hourlyBucketsFilter() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.reminderAccepted(.eyeBreak), at: at(hour: 9), calendar: calendar)
        let events = log.events(on: noon, calendar: calendar)
        #expect(HourlyActivity.buckets(from: events, activity: .water, calendar: calendar)[9].count == 1)
        #expect(HourlyActivity.buckets(from: events, activity: .eyeBreak, calendar: calendar)[9].count == 1)
        #expect(HourlyActivity.buckets(from: events, activity: .focus, calendar: calendar)[9].count == 0)
    }

    @Test("skipped reminders are left out of the activity line by default")
    func hourlyIgnoresSkips() {
        var log = ActivityLog()
        log.apply(.reminderIgnored(.eyeBreak), at: at(hour: 9), calendar: calendar)
        let events = log.events(on: noon, calendar: calendar)
        #expect(HourlyActivity.buckets(from: events, calendar: calendar)[9].count == 0)
        #expect(HourlyActivity.buckets(from: events, positiveOnly: false, calendar: calendar)[9].count == 1)
    }

    @Test("a day with nothing in it has no busiest hour")
    func noBusiestHourWhenEmpty() {
        let buckets = HourlyActivity.buckets(from: [], calendar: calendar)
        #expect(HourlyActivity.busiestHour(buckets) == nil)
    }

    // MARK: Export

    @Test("the detail export is what makes 'export before clearing' honest")
    func eventsExportHasTheDetail() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        log.apply(.focusSessionCompleted(minutes: 25), at: at(hour: 14), calendar: calendar)

        let csv = log.eventsCSV(calendar: calendar)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.first == "Date and time,Activity,What happened,Minutes")
        #expect(lines.count == 3)
        // The clock time is the whole point -- the daily CSV cannot express it.
        #expect(lines[1].contains("09:00:00"))
        #expect(lines[1].contains("Water"))
        #expect(lines[2].contains("14:00:00"))
        #expect(lines[2].hasSuffix("25"))
    }

    @Test("an empty detail export is still a valid CSV")
    func eventsExportEmpty() {
        let csv = ActivityLog().eventsCSV(calendar: calendar)
        #expect(csv == "Date and time,Activity,What happened,Minutes\n")
    }

    // MARK: Monthly clear-out

    @Test("detail from this month is never offered for clearing")
    func noNoticeForCurrentMonth() {
        var log = ActivityLog()
        log.apply(.glassLogged(goal: 8), at: at(hour: 9), calendar: calendar)
        #expect(DataRetention.notice(for: log, at: noon, calendar: calendar) == .none)
    }

    @Test("detail from before this month is offered, with a count")
    func noticeForOlderDetail() {
        var log = ActivityLog()
        let lastMonth = calendar.date(byAdding: .day, value: -40, to: noon)!
        log.apply(.glassLogged(goal: 8), at: lastMonth, calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: lastMonth, calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: noon, calendar: calendar)

        let notice = DataRetention.notice(for: log, at: noon, calendar: calendar)
        guard case .offerClearing(let events, let cutoff) = notice else {
            Issue.record("expected an offer, got \(notice)")
            return
        }
        #expect(events == 2, "only the stale ones are counted")
        #expect(cutoff == DataRetention.monthStart(for: noon, calendar: calendar))
    }

    @Test("clearing removes old detail and keeps every daily total")
    func clearingKeepsSummaries() {
        var log = ActivityLog()
        let lastMonth = calendar.date(byAdding: .day, value: -40, to: noon)!
        log.apply(.glassLogged(goal: 8), at: lastMonth, calendar: calendar)
        log.apply(.glassLogged(goal: 8), at: noon, calendar: calendar)
        let daysBefore = log.days.count

        log.clearEvents(before: DataRetention.monthStart(for: noon, calendar: calendar))

        #expect(log.events.count == 1, "this month's detail survives")
        #expect(log.days.count == daysBefore, "no daily total is ever removed")
        #expect(log.days.first?.glasses == 1, "last month's total is still there")
        #expect(DataRetention.notice(for: log, at: noon, calendar: calendar) == .none)
    }

    @Test("clearing does not break a streak earned last month")
    func clearingPreservesStreaks() {
        var log = ActivityLog()
        // Four goal-meeting days that straddle the month boundary.
        for offset in [-33, -32, -31, -30] {
            let day = calendar.date(byAdding: .day, value: offset, to: noon)!
            log.apply(.glassLogged(goal: 1), at: day, calendar: calendar)
        }
        let bestBefore = log.bestStreak(calendar: calendar)
        #expect(bestBefore == 4)

        log.clearEvents(before: DataRetention.monthStart(for: noon, calendar: calendar))
        #expect(log.bestStreak(calendar: calendar) == bestBefore,
                "streaks come from the summaries, which are never cleared")
    }

    @Test("the engine's clear-out only ever removes old timestamps")
    func engineClearIsNarrow() {
        var settings = AiTwinSettings.defaults
        settings.stretchEnabled = false
        let clock = FakeClock()
        let engine = ReminderEngine(settings: settings, clock: clock, calendar: calendar,
                                    waterLogStore: InMemoryWaterLogStore())
        engine.logWaterManually()
        clock.advance(60)
        engine.logWaterManually()

        let daysBefore = engine.activityLog.days.count
        let glassesBefore = engine.activityLog.days.first?.glasses

        // A cutoff in the future, so everything is stale.
        engine.clearEventDetail(before: clock.now.addingTimeInterval(3600))

        #expect(engine.activityLog.events.isEmpty)
        #expect(engine.activityLog.days.count == daysBefore)
        #expect(engine.activityLog.days.first?.glasses == glassesBefore)
    }

    @Test("the notice explains itself without threatening a deadline")
    func explanationReadsPlainly() {
        let cutoff = DataRetention.monthStart(for: noon, calendar: calendar)
        let text = DataRetention.explanation(events: 12, upTo: cutoff, calendar: calendar)
        #expect(text.contains("12 detailed entries"))
        #expect(text.contains("October"))
        #expect(text.contains("kept forever"))
        // Nothing is deleted on a timer, so no countdown is claimed.
        #expect(text.lowercased().contains("days") == false)
    }

    @Test("one stale entry is described in the singular")
    func explanationSingular() {
        let cutoff = DataRetention.monthStart(for: noon, calendar: calendar)
        #expect(DataRetention.explanation(events: 1, upTo: cutoff, calendar: calendar)
            .contains("1 detailed entry"))
    }
}
