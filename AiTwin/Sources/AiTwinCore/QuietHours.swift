import Foundation

/// A daily do-not-disturb window, stored as minutes since midnight.
///
/// Minutes-since-midnight rather than `Date` because the window repeats every
/// day and must not carry a calendar date with it. The interesting case is a
/// window that crosses midnight (22:00 -> 07:00), which is the common one for a
/// sleep schedule and the one a naive `start <= t && t < end` gets wrong.
public struct QuietHours: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Inclusive start, minutes since midnight (0..<1440).
    public var startMinutes: Int
    /// Exclusive end, minutes since midnight (0..<1440).
    public var endMinutes: Int

    public init(isEnabled: Bool = false, startMinutes: Int = 22 * 60, endMinutes: Int = 7 * 60) {
        self.isEnabled = isEnabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public static let disabled = QuietHours()

    /// Whether `minutes` falls inside the window.
    public func contains(minuteOfDay minutes: Int) -> Bool {
        guard isEnabled else { return false }
        // An empty window (start == end) silences nothing; treating it as
        // "always quiet" would let a mis-set slider mute the app forever.
        guard startMinutes != endMinutes else { return false }
        if startMinutes < endMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        }
        // Crosses midnight: inside if after the start OR before the end.
        return minutes >= startMinutes || minutes < endMinutes
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return contains(minuteOfDay: minutes)
    }

    public static func format(minuteOfDay minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
