import Foundation

/// What happened on one day.
///
/// Every field is recorded from the first launch, including ones no view shows
/// yet. History cannot be backfilled: the day a stats screen ships, it can only
/// chart what was already being written down.
public struct DailyRecord: Codable, Equatable, Sendable {
    /// Midnight local time for the day this covers.
    public var dayStart: Date
    public var glasses: Int
    /// The goal in force that day, so an old day is not re-judged against a
    /// goal the user has since changed.
    public var waterGoal: Int

    public var eyeBreaksAccepted: Int
    public var eyeBreaksSnoozed: Int
    /// Timed out with nobody responding.
    public var eyeBreaksIgnored: Int

    public var stretchesAccepted: Int
    public var stretchesSnoozed: Int
    public var stretchesIgnored: Int

    public var focusSessionsCompleted: Int
    public var focusMinutes: Double

    public init(
        dayStart: Date,
        glasses: Int = 0,
        waterGoal: Int = 8,
        eyeBreaksAccepted: Int = 0,
        eyeBreaksSnoozed: Int = 0,
        eyeBreaksIgnored: Int = 0,
        stretchesAccepted: Int = 0,
        stretchesSnoozed: Int = 0,
        stretchesIgnored: Int = 0,
        focusSessionsCompleted: Int = 0,
        focusMinutes: Double = 0
    ) {
        self.dayStart = dayStart
        self.glasses = glasses
        self.waterGoal = waterGoal
        self.eyeBreaksAccepted = eyeBreaksAccepted
        self.eyeBreaksSnoozed = eyeBreaksSnoozed
        self.eyeBreaksIgnored = eyeBreaksIgnored
        self.stretchesAccepted = stretchesAccepted
        self.stretchesSnoozed = stretchesSnoozed
        self.stretchesIgnored = stretchesIgnored
        self.focusSessionsCompleted = focusSessionsCompleted
        self.focusMinutes = focusMinutes
    }

    public var metWaterGoal: Bool { waterGoal > 0 && glasses >= waterGoal }
    public var breaksOffered: Int { eyeBreaksAccepted + eyeBreaksSnoozed + eyeBreaksIgnored }

    /// Share of offered eye breaks actually taken. Nil when none were offered,
    /// so an untouched day is not charted as 0%.
    public var breakAcceptanceRate: Double? {
        guard breaksOffered > 0 else { return nil }
        return Double(eyeBreaksAccepted) / Double(breaksOffered)
    }
}

/// Something worth writing into the day's record.
public enum ActivityEvent: Equatable, Sendable {
    case glassLogged(goal: Int)
    case reminderAccepted(ReminderKind)
    case reminderSnoozed(ReminderKind)
    case reminderIgnored(ReminderKind)
    case focusSessionCompleted(minutes: Double)
}

/// Rolling day-by-day history, plus the streak maths.
public struct ActivityLog: Codable, Equatable, Sendable {
    /// Oldest first. Only days with something recorded are stored, so an app
    /// left closed for a week does not accumulate empty rows.
    ///
    /// **Kept indefinitely.** A day's summary costs a couple of hundred bytes,
    /// so twenty years is about 1.5 MB -- less than two frames of character
    /// art. Deleting them would buy nothing and would cap the best streak at
    /// however long the retention window happened to be.
    public private(set) var days: [DailyRecord]

    /// Individual events with the time they happened, oldest first.
    ///
    /// This is what the by-hour view of today is drawn from; the daily records
    /// above only count things, they do not remember when. Far bulkier per day
    /// than a summary, which is why this is the part the monthly clear-out
    /// removes -- see `DataRetention`.
    public private(set) var events: [TimedEvent]

    public init(days: [DailyRecord] = [], events: [TimedEvent] = []) {
        self.days = days
        self.events = events
    }

    // Older stored logs have no `events` key, so decode it as empty rather than
    // failing and throwing away someone's whole history.
    private enum CodingKeys: String, CodingKey { case days, events }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([DailyRecord].self, forKey: .days) ?? []
        events = try container.decodeIfPresent([TimedEvent].self, forKey: .events) ?? []
    }

    public func record(on date: Date, calendar: Calendar = .current) -> DailyRecord? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.dayStart == start }
    }

    /// Applies an event to the given day, creating the day if needed.
    public mutating func apply(_ event: ActivityEvent, at date: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        var record = days.first { $0.dayStart == start } ?? DailyRecord(dayStart: start)

        switch event {
        case .glassLogged(let goal):
            record.glasses += 1
            record.waterGoal = goal
        case .reminderAccepted(let kind):
            switch kind {
            case .eyeBreak: record.eyeBreaksAccepted += 1
            case .stretch:  record.stretchesAccepted += 1
            case .water:    break   // the glass itself is the record
            }
        case .reminderSnoozed(let kind):
            switch kind {
            case .eyeBreak: record.eyeBreaksSnoozed += 1
            case .stretch:  record.stretchesSnoozed += 1
            case .water:    break
            }
        case .reminderIgnored(let kind):
            switch kind {
            case .eyeBreak: record.eyeBreaksIgnored += 1
            case .stretch:  record.stretchesIgnored += 1
            case .water:    break
            }
        case .focusSessionCompleted(let minutes):
            record.focusSessionsCompleted += 1
            record.focusMinutes += minutes
        }

        days.removeAll { $0.dayStart == start }
        days.append(record)
        days.sort { $0.dayStart < $1.dayStart }

        if let timed = TimedEvent(event, at: date) {
            events.append(timed)
            events.sort { $0.at < $1.at }
        }
    }

    /// Drops timestamped events from before `cutoff`, keeping every daily
    /// summary. Only ever called after the user has explicitly agreed.
    public mutating func clearEvents(before cutoff: Date) {
        events.removeAll { $0.at < cutoff }
    }

    /// The events recorded on one day, in order.
    public func events(on date: Date, calendar: Calendar = .current) -> [TimedEvent] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.at >= start && $0.at < end }
    }

    /// The last `count` days ending today, including days with no activity, so a
    /// chart always has a full week of bars.
    public func recentDays(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [DailyRecord] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return days.first { $0.dayStart == day } ?? DailyRecord(dayStart: day)
        }
    }

    // MARK: Streaks

    /// Consecutive days up to today on which the water goal was met.
    ///
    /// Today counts only once the goal is actually met, but an unfinished today
    /// does **not** break a streak earned yesterday -- otherwise every morning
    /// would show a zero and the number would be useless before lunch.
    public func currentStreak(endingAt date: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        var streak = 0
        var cursor = today

        if !(record(on: today, calendar: calendar)?.metWaterGoal ?? false) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }
        while let day = days.first(where: { $0.dayStart == cursor }), day.metWaterGoal {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// The longest run of goal-meeting days anywhere in the retained history.
    public func bestStreak(calendar: Calendar = .current) -> Int {
        var best = 0, run = 0
        var previousDay: Date?
        for day in days where day.metWaterGoal {
            if let previous = previousDay,
               let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               expected == day.dayStart {
                run += 1
            } else {
                run = 1
            }
            previousDay = day.dayStart
            best = max(best, run)
        }
        return best
    }

    /// Streak lengths worth celebrating.
    public static let milestones = [3, 7, 14, 30, 100]

    /// The milestone reached exactly today, if any.
    public static func milestone(for streak: Int) -> Int? {
        milestones.contains(streak) ? streak : nil
    }

    // MARK: Export

    /// The history as CSV, newest last, for opening in a spreadsheet.
    ///
    /// CSV rather than a chart image or a proprietary blob: it opens in
    /// Excel, Numbers and every analysis tool without an importer, and it is
    /// readable in a text editor if it ever needs checking by hand.
    ///
    /// Volumes are written in millilitres so the numbers are absolute — glasses
    /// would be meaningless once the glass size changes.
    /// The timestamped detail as CSV: one row per event, with the clock time.
    ///
    /// This is the half the monthly clear-out removes, so it is the half an
    /// export has to be able to preserve. Exporting only the daily totals --
    /// which are never deleted -- would have made "export before clearing"
    /// meaningless.
    public func eventsCSV(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = ["Date and time,Activity,What happened,Minutes"]
        for event in events {
            let activity = event.kind.activity.displayName
            let what = event.kind.rawValue
            let minutes = event.minutes > 0 ? String(Int(event.minutes)) : ""
            lines.append("\(formatter.string(from: event.at)),\(activity),\(what),\(minutes)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func csv(intake: WaterIntake, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        var lines = ["date,water_ml,goal_ml,goal_met,glasses,"
                     + "eye_breaks_taken,eye_breaks_snoozed,eye_breaks_missed,"
                     + "stretches_taken,stretches_snoozed,stretches_missed,"
                     + "focus_sessions,focus_minutes"]
        for day in days.sorted(by: { $0.dayStart < $1.dayStart }) {
            let millilitres = intake.millilitres(forGlasses: day.glasses)
            lines.append([
                formatter.string(from: day.dayStart),
                "\(millilitres)",
                "\(intake.dailyGoal)",
                millilitres >= intake.dailyGoal ? "yes" : "no",
                "\(day.glasses)",
                "\(day.eyeBreaksAccepted)", "\(day.eyeBreaksSnoozed)", "\(day.eyeBreaksIgnored)",
                "\(day.stretchesAccepted)", "\(day.stretchesSnoozed)", "\(day.stretchesIgnored)",
                "\(day.focusSessionsCompleted)",
                String(format: "%.0f", day.focusMinutes),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A filename that sorts chronologically and says what it is.
    public static func exportFilename(on date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        return "AiTwin-history-\(formatter.string(from: date)).csv"
    }

    // MARK: Merging

    /// Combines two histories of the same person on two machines.
    ///
    /// Per day, the larger count of each metric wins. Counts only ever increase
    /// within a day, so the larger number is the one that saw more of that day
    /// -- and taking the max can never invent activity that did not happen,
    /// which summing absolutely could when both machines saw the same glass.
    public func merged(with other: ActivityLog) -> ActivityLog {
        var byDay: [Date: DailyRecord] = [:]
        for day in days { byDay[day.dayStart] = day }
        for day in other.days {
            guard let mine = byDay[day.dayStart] else {
                byDay[day.dayStart] = day
                continue
            }
            byDay[day.dayStart] = DailyRecord(
                dayStart: day.dayStart,
                glasses: max(mine.glasses, day.glasses),
                // The goal comes from whichever record saw more of that day,
                // never the larger of the two. Taking the max would let a goal
                // raised on another Mac retroactively un-meet a day already
                // completed here, silently breaking a streak that was earned.
                waterGoal: mine.glasses >= day.glasses ? mine.waterGoal : day.waterGoal,
                eyeBreaksAccepted: max(mine.eyeBreaksAccepted, day.eyeBreaksAccepted),
                eyeBreaksSnoozed: max(mine.eyeBreaksSnoozed, day.eyeBreaksSnoozed),
                eyeBreaksIgnored: max(mine.eyeBreaksIgnored, day.eyeBreaksIgnored),
                stretchesAccepted: max(mine.stretchesAccepted, day.stretchesAccepted),
                stretchesSnoozed: max(mine.stretchesSnoozed, day.stretchesSnoozed),
                stretchesIgnored: max(mine.stretchesIgnored, day.stretchesIgnored),
                focusSessionsCompleted: max(mine.focusSessionsCompleted, day.focusSessionsCompleted),
                focusMinutes: max(mine.focusMinutes, day.focusMinutes)
            )
        }
        return ActivityLog(days: byDay.values.sorted { $0.dayStart < $1.dayStart })
    }

    // MARK: Totals

    public func totalGlasses(inLast count: Int, endingAt date: Date, calendar: Calendar = .current) -> Int {
        recentDays(count, endingAt: date, calendar: calendar).reduce(0) { $0 + $1.glasses }
    }

    public func totalFocusMinutes(inLast count: Int, endingAt date: Date, calendar: Calendar = .current) -> Double {
        recentDays(count, endingAt: date, calendar: calendar).reduce(0) { $0 + $1.focusMinutes }
    }
}

public protocol ActivityLogStoring: AnyObject {
    func load() -> ActivityLog
    func save(_ log: ActivityLog)
}

public final class InMemoryActivityLogStore: ActivityLogStoring {
    private var log: ActivityLog
    public init(_ log: ActivityLog = ActivityLog()) { self.log = log }
    public func load() -> ActivityLog { log }
    public func save(_ log: ActivityLog) { self.log = log }
}

public final class UserDefaultsActivityLogStore: ActivityLogStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.aitwin.activity.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ActivityLog {
        guard let data = defaults.data(forKey: key) else { return ActivityLog() }
        // Corrupt history must never stop the app launching; an empty log is a
        // survivable loss, a crash on startup is not.
        return (try? JSONDecoder().decode(ActivityLog.self, from: data)) ?? ActivityLog()
    }

    public func save(_ log: ActivityLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: key)
    }
}
