import Foundation

/// Decides whether the character may say something unprompted.
///
/// The limits are the feature, not a safety valve bolted on afterwards. A
/// desktop pet that chats freely is charming on day one and uninstalled by day
/// three, so this refuses far more often than it allows: at most once every
/// ninety minutes, never near a real reminder, never while you are focused,
/// away, paused, or in quiet hours.
public struct ChatterScheduler: Equatable, Sendable {

    public enum Frequency: String, Codable, CaseIterable, Sendable, Identifiable {
        case off
        case rare
        case occasional

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .off:        return "Never"
            case .rare:       return "Rarely"
            case .occasional: return "Occasionally"
            }
        }

        /// Minimum gap between two unprompted lines.
        public var minimumGap: TimeInterval {
            switch self {
            case .off:        return .infinity
            case .rare:       return 90 * 60
            case .occasional: return 35 * 60
            }
        }

        public var detail: String {
            switch self {
            case .off:        return "She only speaks when reminding you"
            case .rare:       return "A few times a day at most"
            case .occasional: return "Every half hour or so"
            }
        }
    }

    /// Never chatter within this long of a real reminder — being nudged and then
    /// chatted at reads as pestering.
    public static let quietAroundReminder: TimeInterval = 10 * 60
    /// Do not chatter to an empty chair.
    public static let maximumIdleSeconds: TimeInterval = 3 * 60

    public var frequency: Frequency
    public var lastChatterAt: Date?
    public var lastReminderAt: Date?

    public init(frequency: Frequency = .rare, lastChatterAt: Date? = nil, lastReminderAt: Date? = nil) {
        self.frequency = frequency
        self.lastChatterAt = lastChatterAt
        self.lastReminderAt = lastReminderAt
    }

    /// Everything that can veto an unprompted line.
    public struct Conditions: Equatable, Sendable {
        public var isPaused: Bool
        public var inQuietHours: Bool
        public var isFocusing: Bool
        public var characterIsBusy: Bool
        public var idleSeconds: TimeInterval

        public init(
            isPaused: Bool = false,
            inQuietHours: Bool = false,
            isFocusing: Bool = false,
            characterIsBusy: Bool = false,
            idleSeconds: TimeInterval = 0
        ) {
            self.isPaused = isPaused
            self.inQuietHours = inQuietHours
            self.isFocusing = isFocusing
            self.characterIsBusy = characterIsBusy
            self.idleSeconds = idleSeconds
        }
    }

    /// Whether she may speak now. Every check is a veto; all must pass.
    public func shouldChatter(at now: Date, conditions: Conditions) -> Bool {
        guard frequency != .off else { return false }
        guard !conditions.isPaused else { return false }
        guard !conditions.inQuietHours else { return false }
        guard !conditions.isFocusing else { return false }
        guard !conditions.characterIsBusy else { return false }
        guard conditions.idleSeconds < Self.maximumIdleSeconds else { return false }

        if let last = lastChatterAt, now.timeIntervalSince(last) < frequency.minimumGap {
            return false
        }
        if let reminder = lastReminderAt,
           now.timeIntervalSince(reminder) < Self.quietAroundReminder {
            return false
        }
        return true
    }

    public mutating func noteChatter(at now: Date) { lastChatterAt = now }
    public mutating func noteReminder(at now: Date) { lastReminderAt = now }
}
