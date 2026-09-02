import Foundation

/// One day's activity, in the form the Progress view reads it.
///
/// The old Progress tab charted whatever the data happened to hold -- a bar per
/// day of raw glasses, and an eye-break acceptance percentage -- and neither
/// answered the question people actually have, which is "what did I do today?".
/// This is that question, in plain quantities.
public struct DaySummary: Equatable, Sendable {

    public let dayStart: Date
    /// Millilitres drunk, so the view never has to know the glass size.
    public let millilitres: Int
    public let goalMillilitres: Int

    public let eyeBreaksTaken: Int
    public let eyeBreaksSnoozed: Int
    public let eyeBreaksMissed: Int

    public let stretchesTaken: Int
    public let stretchesSnoozed: Int
    public let stretchesMissed: Int

    public let focusSessions: Int
    public let focusMinutes: Double

    public init(
        dayStart: Date,
        millilitres: Int, goalMillilitres: Int,
        eyeBreaksTaken: Int, eyeBreaksSnoozed: Int, eyeBreaksMissed: Int,
        stretchesTaken: Int, stretchesSnoozed: Int, stretchesMissed: Int,
        focusSessions: Int, focusMinutes: Double
    ) {
        self.dayStart = dayStart
        self.millilitres = millilitres
        self.goalMillilitres = goalMillilitres
        self.eyeBreaksTaken = eyeBreaksTaken
        self.eyeBreaksSnoozed = eyeBreaksSnoozed
        self.eyeBreaksMissed = eyeBreaksMissed
        self.stretchesTaken = stretchesTaken
        self.stretchesSnoozed = stretchesSnoozed
        self.stretchesMissed = stretchesMissed
        self.focusSessions = focusSessions
        self.focusMinutes = focusMinutes
    }

    /// Everything put off or ignored, across both kinds of break. This is the
    /// "how many did I skip" number.
    public var skipped: Int {
        eyeBreaksSnoozed + eyeBreaksMissed + stretchesSnoozed + stretchesMissed
    }

    public var metWaterGoal: Bool { goalMillilitres > 0 && millilitres >= goalMillilitres }

    /// 0...1 against the day's own goal, capped so a big day does not overflow
    /// a progress bar.
    public var waterProgress: Double {
        guard goalMillilitres > 0 else { return 0 }
        return min(1, Double(millilitres) / Double(goalMillilitres))
    }

    public var didAnything: Bool {
        millilitres > 0 || eyeBreaksTaken > 0 || stretchesTaken > 0
            || focusSessions > 0 || skipped > 0
    }

    /// Builds a summary from a stored day, converting glasses into volume with
    /// the glass size currently configured.
    public static func from(_ record: DailyRecord, intake: WaterIntake) -> DaySummary {
        DaySummary(
            dayStart: record.dayStart,
            millilitres: record.glasses * intake.glassSize,
            goalMillilitres: record.waterGoal * intake.glassSize,
            eyeBreaksTaken: record.eyeBreaksAccepted,
            eyeBreaksSnoozed: record.eyeBreaksSnoozed,
            eyeBreaksMissed: record.eyeBreaksIgnored,
            stretchesTaken: record.stretchesAccepted,
            stretchesSnoozed: record.stretchesSnoozed,
            stretchesMissed: record.stretchesIgnored,
            focusSessions: record.focusSessionsCompleted,
            focusMinutes: record.focusMinutes
        )
    }
}

/// Today's activity spread across the hours it happened in.
///
/// Twenty-four buckets whatever the day looked like, so the line has a stable
/// x-axis and a quiet morning reads as a flat start rather than a missing one.
public enum HourlyActivity {

    public struct Bucket: Equatable, Sendable {
        public let hour: Int
        public let count: Int
        public init(hour: Int, count: Int) {
            self.hour = hour
            self.count = count
        }
    }

    /// - Parameter activity: nil counts every kind of event together.
    public static func buckets(
        from events: [TimedEvent],
        activity: TimedEvent.Activity? = nil,
        positiveOnly: Bool = true,
        calendar: Calendar = .current
    ) -> [Bucket] {
        var counts = Array(repeating: 0, count: 24)
        for event in events {
            if let activity, event.kind.activity != activity { continue }
            if positiveOnly, !event.kind.isPositive { continue }
            let hour = calendar.component(.hour, from: event.at)
            guard hour >= 0, hour < 24 else { continue }
            counts[hour] += 1
        }
        return counts.enumerated().map { Bucket(hour: $0.offset, count: $0.element) }
    }

    /// The busiest hour, for labelling. Nil when nothing happened at all.
    public static func busiestHour(_ buckets: [Bucket]) -> Bucket? {
        guard let best = buckets.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        return best
    }
}
