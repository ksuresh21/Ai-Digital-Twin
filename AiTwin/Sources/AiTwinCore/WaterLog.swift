import Foundation

/// Glasses of water logged today, against a daily goal.
///
/// Stores the *start of the day* it belongs to rather than a formatted string,
/// so rollover is a date comparison and not string parsing. The counter resets
/// when the day changes, which happens the next time the app looks at it -- no
/// midnight timer is needed, and none would survive sleep anyway.
public struct WaterLog: Codable, Equatable, Sendable {
    public private(set) var glasses: Int
    public private(set) var dayStart: Date

    public init(glasses: Int, dayStart: Date) {
        self.glasses = glasses
        self.dayStart = dayStart
    }

    public static func empty(at date: Date, calendar: Calendar = .current) -> WaterLog {
        WaterLog(glasses: 0, dayStart: calendar.startOfDay(for: date))
    }

    /// Returns the log as it should be for `date`, resetting if the day rolled
    /// over. Also resets if the day went *backwards*, which happens when the
    /// system clock is corrected.
    public func rolledOver(to date: Date, calendar: Calendar = .current) -> WaterLog {
        let today = calendar.startOfDay(for: date)
        return today == dayStart ? self : WaterLog(glasses: 0, dayStart: today)
    }

    public mutating func add(_ count: Int = 1, at date: Date, calendar: Calendar = .current) {
        self = rolledOver(to: date, calendar: calendar)
        glasses = max(0, glasses + count)
    }

    public func hasReachedGoal(_ intake: WaterIntake) -> Bool {
        intake.hasReachedGoal(glasses: glasses)
    }

    public func millilitres(_ intake: WaterIntake) -> Int {
        intake.millilitres(forGlasses: glasses)
    }

    /// 0...1, clamped so an over-achiever does not overflow a progress bar.
    public func progress(_ intake: WaterIntake) -> Double {
        intake.progress(glasses: glasses)
    }
}

public protocol WaterLogStoring: AnyObject {
    func load() -> WaterLog?
    func save(_ log: WaterLog)
}

public final class InMemoryWaterLogStore: WaterLogStoring {
    private var log: WaterLog?
    public init(_ log: WaterLog? = nil) { self.log = log }
    public func load() -> WaterLog? { log }
    public func save(_ log: WaterLog) { self.log = log }
}

public final class UserDefaultsWaterLogStore: WaterLogStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.aitwin.waterlog.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> WaterLog? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WaterLog.self, from: data)
    }

    public func save(_ log: WaterLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: key)
    }
}
