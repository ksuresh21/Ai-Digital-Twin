import Foundation

/// One thing that happened, and when.
///
/// The daily records in `ActivityLog` count what happened; this remembers the
/// clock time, which is the only way to draw "your day, by hour". It could not
/// be added retroactively -- a chart of today can only start from the day this
/// began recording.
///
/// Deliberately a flat enum with no associated values so it encodes as a short
/// string. At roughly forty bytes an event this is the bulky half of the log,
/// which is why it is the half the monthly clear-out removes.
public struct TimedEvent: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
        case glass
        case eyeBreakTaken
        case eyeBreakSnoozed
        case eyeBreakMissed
        case stretchTaken
        case stretchSnoozed
        case stretchMissed
        case focusCompleted

        /// Which activity this belongs to, for grouping in the day view.
        public var activity: Activity {
            switch self {
            case .glass: return .water
            case .eyeBreakTaken, .eyeBreakSnoozed, .eyeBreakMissed: return .eyeBreak
            case .stretchTaken, .stretchSnoozed, .stretchMissed: return .stretch
            case .focusCompleted: return .focus
            }
        }

        /// True when the user did the thing rather than putting it off.
        public var isPositive: Bool {
            switch self {
            case .glass, .eyeBreakTaken, .stretchTaken, .focusCompleted: return true
            case .eyeBreakSnoozed, .eyeBreakMissed, .stretchSnoozed, .stretchMissed: return false
            }
        }
    }

    /// The four things the app actually tracks. Used to label the day view and
    /// to pick which small chart a number belongs in.
    public enum Activity: String, Codable, Equatable, Sendable, CaseIterable {
        case water, eyeBreak, stretch, focus

        public var displayName: String {
            switch self {
            case .water:    return "Water"
            case .eyeBreak: return "Eye breaks"
            case .stretch:  return "Stretches"
            case .focus:    return "Focus"
            }
        }
    }

    public let at: Date
    public let kind: Kind
    /// Minutes, for a completed focus session. Zero for everything else.
    public let minutes: Double

    public init(at: Date, kind: Kind, minutes: Double = 0) {
        self.at = at
        self.kind = kind
        self.minutes = minutes
    }

    /// Translates a domain event, or nil for one with nothing to timestamp.
    ///
    /// An accepted *water* reminder returns nil on purpose: logging the glass
    /// is the event, and recording both would double-count every drink.
    init?(_ event: ActivityEvent, at date: Date) {
        switch event {
        case .glassLogged:
            self.init(at: date, kind: .glass)
        case .reminderAccepted(let kind):
            switch kind {
            case .eyeBreak: self.init(at: date, kind: .eyeBreakTaken)
            case .stretch:  self.init(at: date, kind: .stretchTaken)
            case .water:    return nil
            }
        case .reminderSnoozed(let kind):
            switch kind {
            case .eyeBreak: self.init(at: date, kind: .eyeBreakSnoozed)
            case .stretch:  self.init(at: date, kind: .stretchSnoozed)
            case .water:    return nil
            }
        case .reminderIgnored(let kind):
            switch kind {
            case .eyeBreak: self.init(at: date, kind: .eyeBreakMissed)
            case .stretch:  self.init(at: date, kind: .stretchMissed)
            case .water:    return nil
            }
        case .focusSessionCompleted(let minutes):
            self.init(at: date, kind: .focusCompleted, minutes: minutes)
        }
    }
}
