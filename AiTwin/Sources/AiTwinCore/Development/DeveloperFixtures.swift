#if AITWIN_DEV
import Foundation

/// Sample data for trying the app out without living with it for a month.
///
/// **This file is compiled only into debug builds.** The `AITWIN_DEV` flag is
/// set in `Package.swift` with `.when(configuration: .debug)`, so a release
/// build does not merely hide this — it does not contain it. Nothing here can
/// reach anyone who installs the app.
public enum DeveloperFixtures {

    /// Thirty days of plausible history: mostly good, with a couple of missed
    /// days so streaks, gaps and a "best streak" all have something to show.
    ///
    /// Deliberately not perfect. A chart where every bar is full teaches you
    /// nothing about whether the chart works.
    public static func sampleActivityLog(
        endingAt today: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityLog {
        var log = ActivityLog()
        let goal = 8

        // Day offset -> glasses drunk. Two deliberate misses break the run, so
        // the current streak and the best streak differ.
        let glassesByDay: [Int: Int] = [
            29: 8, 28: 9, 27: 8, 26: 8, 25: 10, 24: 8, 23: 8,   // a 7-day run
            22: 4,                                              // missed
            21: 8, 20: 8, 19: 9, 18: 8,
            17: 3,                                              // missed
            16: 8, 15: 8, 14: 8, 13: 11, 12: 8, 11: 8, 10: 8,
            9: 5,                                               // missed
            8: 8, 7: 8, 6: 9, 5: 8, 4: 8, 3: 8, 2: 8, 1: 8, 0: 6,
        ]

        for (offset, glasses) in glassesByDay.sorted(by: { $0.key > $1.key }) {
            guard let day = calendar.date(byAdding: .day, value: -offset,
                                          to: calendar.startOfDay(for: today)) else { continue }
            // Midday, so the entry lands unambiguously inside the day.
            let stamp = day.addingTimeInterval(12 * 3600)
            for _ in 0..<glasses {
                log.apply(.glassLogged(goal: goal), at: stamp, calendar: calendar)
            }

            // Eye breaks: mostly taken, sometimes snoozed, occasionally missed —
            // so the accepted/snoozed/missed bar has all three segments.
            let offered = 3 + (offset % 3)
            for index in 0..<offered {
                let event: ActivityEvent
                switch (offset + index) % 5 {
                case 0:  event = .reminderSnoozed(.eyeBreak)
                case 1:  event = .reminderIgnored(.eyeBreak)
                default: event = .reminderAccepted(.eyeBreak)
                }
                log.apply(event, at: stamp, calendar: calendar)
            }

            if offset % 2 == 0 {
                log.apply(.reminderAccepted(.stretch), at: stamp, calendar: calendar)
            }
            if offset % 3 == 0 {
                log.apply(.focusSessionCompleted(minutes: 25), at: stamp, calendar: calendar)
                log.apply(.focusSessionCompleted(minutes: 25), at: stamp, calendar: calendar)
            }
        }
        return log
    }

    /// A log with nothing in it, for checking the empty states read properly —
    /// the case a populated fixture hides.
    public static func emptyActivityLog() -> ActivityLog { ActivityLog() }
}
#endif
