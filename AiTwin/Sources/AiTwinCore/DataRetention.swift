import Foundation

/// When to offer clearing out the detailed history, and what to say about it.
///
/// Two kinds of history are stored and they are treated very differently.
///
/// **Daily summaries stay forever.** A day costs a couple of hundred bytes, so
/// twenty years is roughly 1.5 MB -- less than two frames of character art.
/// Deleting them would save nothing and would cap the best streak at whatever
/// the retention window happened to be, which makes the streak meaningless.
///
/// **Timestamped events are the bulky half**, perhaps sixteen times a summary
/// on a busy day, and they only exist to draw "today, by hour". Last month's
/// hour-by-hour detail is not worth keeping, so once a month the app offers to
/// clear it.
///
/// Nothing is ever deleted on a timer. The notice appears and stays until the
/// user either exports or explicitly agrees, so a Mac left closed for a
/// fortnight cannot lose anything while nobody was looking.
public enum DataRetention {

    /// What the Progress view should show about old detail.
    public enum Notice: Equatable, Sendable {
        /// Nothing to offer: no detail older than this month.
        case none
        /// There is last-month detail worth exporting before it goes.
        case offerClearing(events: Int, upTo: Date)
    }

    /// Start of the calendar month containing `date`. Everything before this is
    /// "last month or older" and eligible to be cleared.
    public static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
    }

    /// Decides whether to show the notice.
    ///
    /// Keyed off the calendar month rather than a fixed day number, because
    /// "the 30th" does not exist in February and a fixed date means the notice
    /// is missed entirely by anyone whose Mac is closed that day. Any day of a
    /// new month is a fine day to be asked.
    public static func notice(
        for log: ActivityLog,
        at date: Date,
        calendar: Calendar = .current
    ) -> Notice {
        let cutoff = monthStart(for: date, calendar: calendar)
        let stale = log.events.filter { $0.at < cutoff }
        guard !stale.isEmpty else { return .none }
        return .offerClearing(events: stale.count, upTo: cutoff)
    }

    /// A plain-language explanation for the banner. No threats and no
    /// countdown: the number and the choice are the whole message.
    public static func explanation(events: Int, upTo cutoff: Date,
                                   calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        // The time zone matters: without it the formatter uses the system zone
        // while the cutoff was computed in the calendar's, and the last instant
        // of October reads as November anywhere east of UTC.
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL"
        let previousMonth = calendar.date(byAdding: .day, value: -1, to: cutoff) ?? cutoff
        let month = formatter.string(from: previousMonth)
        let detail = events == 1 ? "1 detailed entry" : "\(events) detailed entries"
        return "\(detail) from \(month) and earlier are still stored. "
            + "Your daily totals and streaks are kept forever — this is only the "
            + "hour-by-hour detail behind them. Export first if you want it."
    }
}
