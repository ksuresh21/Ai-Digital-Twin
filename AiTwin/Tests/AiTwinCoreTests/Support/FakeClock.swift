import Foundation
@testable import AiTwinCore

/// A clock a test can drag forward by hand.
///
/// This is what makes a 40-minute eye-break test finish in microseconds. Every
/// timing test in this suite advances this rather than sleeping, so the whole
/// suite is deterministic and runs in well under a second.
final class FakeClock: Clock {
    var now: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = start
    }

    /// Moves time forward.
    func advance(_ interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }

    /// Moves to a specific wall-clock time on the clock's current day. Used by
    /// the quiet-hours tests.
    func setTimeOfDay(hour: Int, minute: Int = 0, calendar: Calendar = .testUTC) {
        let start = calendar.startOfDay(for: now)
        now = start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }
}

extension Calendar {
    /// A fixed-zone calendar so date-boundary tests do not depend on where the
    /// machine running them happens to be.
    static var testUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

/// Collects engine events so a test can assert on what was emitted, in order.
final class EventRecorder {
    private(set) var events: [ReminderEvent] = []

    func record(_ event: ReminderEvent) {
        events.append(event)
    }

    var dueReminders: [ReminderKind] {
        events.compactMap {
            if case .reminderDue(let kind, _) = $0 { return kind }
            return nil
        }
    }

    var lastMessage: String? {
        events.reversed().compactMap {
            if case .reminderDue(_, let message) = $0 { return message }
            return nil
        }.first
    }

    func clear() { events.removeAll() }
}
