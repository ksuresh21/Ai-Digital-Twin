import Foundation

/// Everything the character says.
///
/// One template list per moment, ten lines each, drawn without repeating until
/// the list runs dry. Ten is enough that you rarely see the same line twice in a
/// session, which is what keeps her feeling like a companion rather than a
/// notification with a face.
///
/// Templates use two tokens:
///   - `{name}`  → ", Suresh" when a name is set, or nothing. Optional.
///   - `{first}` → "Suresh". A line containing this **requires** a name and is
///     skipped entirely when none is set.
///
/// So roughly half of every list greets you personally once you have entered a
/// name, and all of it still reads naturally when you have not.
public final class MessageCatalog {

    private var unusedByKey: [String: [String]] = [:]
    private let randomSource: () -> Double

    /// - Parameter randomSource: returns a value in 0..<1. Injected so tests can
    ///   make selection deterministic.
    public init(randomSource: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.randomSource = randomSource
    }

    // MARK: - Template lists

    public static let waterMessages = [
        "Water break 💧",
        "Sip time{name}!",
        "Hydrate{name} 💧",
        "Go get a glass ✨",
        "{first}, water. Now 💧",
        "Thirsty? You are 🚰",
        "One glass{name}. Quick.",
        "Your plant-self needs a drink 🌱",
        "Psst — water 💧",
        "{first}! Hydration check 🚰",
    ]

    public static let eyeBreakMessages = [
        "Eyes off, please 👀",
        "Look far away{name} ✨",
        "Blink. Breathe. Look up.",
        "{first}, rest your eyes 👀",
        "Screen break{name}!",
        "Twenty seconds. Go 👀",
        "I'm tired too 😴",
        "Find a window{name} 🪟",
        "{first} — look at something far 🌤️",
        "Eyes need a stretch 👁️",
    ]

    /// Shown while the eye-break countdown runs.
    public static let breakStartMessages = [
        "Look away{name} 👀",
        "Eyes up! Something far.",
        "{first}, out the window 🪟",
        "Hold it… ✨",
        "Far away. Nice and easy.",
        "Blink slowly{name} 😌",
        "That's it. Keep looking.",
        "{first} — no peeking 👀",
        "Rest them properly{name}.",
        "Almost there 🌤️",
    ]

    /// Shown when the eye break finishes.
    public static let breakDoneMessages = [
        "All done 👀✨",
        "Nice one{name}!",
        "Eyes happy 💙",
        "{first}, that's the way ✨",
        "Refreshed? Good.",
        "Back to it{name} 💪",
        "Well done 🌤️",
        "{first} — proud of you ✨",
        "That's the good stuff 😌",
        "See? Easy 💙",
    ]

    public static let goalMessages = [
        "Goal hit 🎉",
        "That's all of them{name}!",
        "{first}, you did it 🎉",
        "Fully watered 🌱",
        "Daily goal — done ✨",
        "Look at you go{name} 💙",
        "{first}! Goal complete 🏆",
        "Hydration champion 🚰",
        "Nailed it{name} 🎉",
        "All glasses down ✨",
    ]

    public static let wakeMessages = [
        "Welcome back{name} 👋",
        "There you are ✨",
        "Hey{name}, missed you 💙",
        "{first}! You're back 👋",
        "Back at it{name}?",
        "Hello again ✨",
        "{first} 👋",
        "Good to see you{name} 💙",
        "Ready when you are ✨",
        "{first}, welcome back 🌤️",
    ]

    public static let morningMessages = [
        "Good morning{name}! ☀️",
        "Morning{name} ☕️",
        "Rise and shine ✨",
        "Hey {first} 👋 Morning!",
        "A fresh day{name} 🌅",
        "{first}! Slept okay?",
        "Morning sunshine ☀️",
        "New day{name} ✨",
        "{first}, let's go ☕️",
        "Up early{name}? 🌅",
    ]

    public static let afternoonMessages = [
        "Good afternoon{name} 👋",
        "Afternoon{name} 🌤️",
        "Hey {first}! 👋",
        "Half the day down ✨",
        "Still going{name}? 💪",
        "{first}, how's it going?",
        "Hi{name} 🌤️",
        "Afternoon check-in ✨",
        "{first} 👋 Doing okay?",
        "Midday{name}! ☀️",
    ]

    public static let eveningMessages = [
        "Good evening{name} 🌙",
        "Evening{name} ✨",
        "Hey {first} 🌙",
        "Winding down{name}?",
        "Long day{name}? 🌆",
        "{first}, made it 🌙",
        "Evening ✨",
        "Almost done{name}? 🌆",
        "{first} 🌙 Take it easy.",
        "Softer hours now{name} ✨",
    ]

    public static let lateNightMessages = [
        "Still up{name}? 🌙",
        "It's late{name} 😴",
        "{first}… bedtime? 🌙",
        "Midnight oil{name}? 🕯️",
        "Sleep soon{name} 😴",
        "{first}, go rest 🌙",
        "Late one{name} ✨",
        "Night owl{name}? 🦉",
        "{first} — wrap it up 😴",
        "Quiet hours{name} 🌙",
    ]

    // MARK: - Time of day

    /// Which part of the day it is.
    ///
    /// The late slot exists so a 2am greeting is not a cheery "Good evening".
    public enum TimeOfDay: String, CaseIterable, Sendable {
        case morning, afternoon, evening, lateNight

        public static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
            switch calendar.component(.hour, from: date) {
            case 5..<12:  return .morning
            case 12..<17: return .afternoon
            case 17..<22: return .evening
            default:      return .lateNight
            }
        }

        public var messages: [String] {
            switch self {
            case .morning:   return MessageCatalog.morningMessages
            case .afternoon: return MessageCatalog.afternoonMessages
            case .evening:   return MessageCatalog.eveningMessages
            case .lateNight: return MessageCatalog.lateNightMessages
            }
        }
    }

    public static func pool(for kind: ReminderKind) -> [String] {
        switch kind {
        case .water:    return waterMessages
        case .eyeBreak: return eyeBreakMessages
        }
    }

    // MARK: - Filling templates

    /// Expands `{name}` and `{first}`.
    ///
    /// Only the first word of the name is used, so entering a full name still
    /// produces "Hey Suresh" rather than "Hey Suresh Kumar".
    public static func fill(_ template: String, name rawName: String) -> String {
        let first = firstName(rawName)
        return template
            .replacingOccurrences(of: "{name}", with: first.isEmpty ? "" : ", \(first)")
            .replacingOccurrences(of: "{first}", with: first)
    }

    public static func firstName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Templates usable given whether a name is available.
    ///
    /// A `{first}` line without a name would read "Hey !", so those are removed
    /// rather than filled with an empty string.
    public static func usable(_ templates: [String], hasName: Bool) -> [String] {
        hasName ? templates : templates.filter { !$0.contains("{first}") }
    }

    // MARK: - Drawing lines

    /// Picks from `templates` without repeating until they have all been used.
    private func pick(_ templates: [String], key: String, name: String) -> String {
        let hasName = !Self.firstName(name).isEmpty
        let usable = Self.usable(templates, hasName: hasName)
        guard !usable.isEmpty else { return "Hi 👋" }

        var remaining = (unusedByKey[key] ?? []).filter(usable.contains)
        if remaining.isEmpty { remaining = usable }
        let index = min(Int(randomSource() * Double(remaining.count)), remaining.count - 1)
        let chosen = remaining.remove(at: index)
        unusedByKey[key] = remaining
        return Self.fill(chosen, name: name)
    }

    public func nextMessage(for kind: ReminderKind, name: String = "") -> String {
        pick(Self.pool(for: kind), key: "reminder.\(kind.rawValue)", name: name)
    }

    public func nextGreeting(for date: Date, name: String = "", calendar: Calendar = .current) -> String {
        let time = TimeOfDay.at(date, calendar: calendar)
        return pick(time.messages, key: "greeting.\(time.rawValue)", name: name)
    }

    public func nextWakeGreeting(for date: Date, name: String = "", calendar: Calendar = .current) -> String {
        pick(Self.wakeMessages, key: "wake", name: name)
    }

    public func nextBreakStartMessage(name: String = "") -> String {
        pick(Self.breakStartMessages, key: "break.start", name: name)
    }

    public func nextBreakDoneMessage(name: String = "") -> String {
        pick(Self.breakDoneMessages, key: "break.done", name: name)
    }

    public func nextGoalMessage(name: String = "") -> String {
        pick(Self.goalMessages, key: "goal", name: name)
    }

    /// Simple time-of-day greeting with no variety, for labels.
    public static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        fill(TimeOfDay.at(date, calendar: calendar).messages[0], name: "")
    }

    public static func wakeGreeting(for date: Date, calendar: Calendar = .current) -> String {
        fill(wakeMessages[0], name: "")
    }

    /// Every list, for tests and for the Settings preview.
    public static var allPools: [(key: String, templates: [String])] {
        [
            ("water", waterMessages), ("eyeBreak", eyeBreakMessages),
            ("breakStart", breakStartMessages), ("breakDone", breakDoneMessages),
            ("goal", goalMessages), ("wake", wakeMessages),
            ("morning", morningMessages), ("afternoon", afternoonMessages),
            ("evening", eveningMessages), ("lateNight", lateNightMessages),
        ]
    }
}
