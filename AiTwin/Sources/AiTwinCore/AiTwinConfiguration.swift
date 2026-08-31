import Foundation

/// Every tunable number in the application, in one place.
///
/// Nothing else in the codebase may contain a bare timing or sizing literal --
/// that is the rule the spec's "do not scatter magic numbers" asks for. Values
/// the *user* can change at runtime live in `AiTwinSettings`; values that are
/// build-time constants live here.
public struct AiTwinConfiguration: Equatable, Sendable {

    // MARK: Reminder timing

    /// How often to nudge for water.
    public var waterReminderInterval: TimeInterval
    /// The eye-break cycle. 40 minutes in production, per the 20-20-20 style rule.
    public var eyeBreakInterval: TimeInterval
    /// How long "Snooze" pushes a reminder back.
    public var snoozeInterval: TimeInterval
    /// Stop counting screen time after this much keyboard/mouse inactivity, so a
    /// lunch break does not count as forty minutes of staring at the screen.
    public var idlePauseThreshold: TimeInterval

    // MARK: Animation

    /// Seconds per animation frame. 1/8s = 8fps, which reads as deliberate,
    /// characterful pixel-art motion rather than a smooth modern animation.
    public var animationFrameDuration: TimeInterval
    /// Horizontal walking speed in points per second.
    public var walkingSpeed: Double
    /// How long the pop-in entrance animation runs before she starts talking.
    ///
    /// Deliberately unhurried: at half a second the entrance was over before
    /// you noticed it happening, which made her seem to blink into existence
    /// rather than arrive.
    public var popDuration: TimeInterval
    /// How long the greeting wave holds before settling into idle.
    public var greetingDuration: TimeInterval
    /// How long the character loiters at the corner after a greeting before
    /// walking back off screen. Short on purpose -- a companion that never
    /// leaves stops being unobtrusive.
    public var idleRestDuration: TimeInterval
    /// How long a reminder bubble stays up before auto-dismissing itself, so an
    /// unattended Mac does not keep a bubble on screen forever.
    public var reminderTimeout: TimeInterval

    // MARK: Layout

    /// On-screen height of the character in points. Width follows the sprite's
    /// aspect ratio.
    public var characterHeight: Double
    /// Gap between the sprite and the screen edge.
    public var edgeMargin: Double
    /// How often the engine is asked to re-check its deadlines.
    public var tickInterval: TimeInterval

    // MARK: Presets

    /// Shipping defaults.
    public static let production = AiTwinConfiguration(
        waterReminderInterval: 45 * 60,
        eyeBreakInterval: 40 * 60,
        snoozeInterval: 5 * 60,
        idlePauseThreshold: 5 * 60,
        animationFrameDuration: 1.0 / 8.0,
        walkingSpeed: 90,
        popDuration: 0.9,
        greetingDuration: 3.5,
        idleRestDuration: 4,
        reminderTimeout: 60,
        characterHeight: 128,
        edgeMargin: 24,
        tickInterval: 1
    )

    /// Fast intervals for development, exposed in Settings as "Test Mode".
    ///
    /// This is a different *configuration*, not a different code path -- the
    /// production reminder logic runs untouched, which is the only way testing
    /// it proves anything.
    public static let testing = AiTwinConfiguration(
        waterReminderInterval: 30,
        eyeBreakInterval: 60,
        snoozeInterval: 10,
        idlePauseThreshold: 15,
        animationFrameDuration: 1.0 / 8.0,
        walkingSpeed: 90,
        popDuration: 0.9,
        greetingDuration: 2.0,
        idleRestDuration: 3,
        reminderTimeout: 20,
        characterHeight: 128,
        edgeMargin: 24,
        tickInterval: 1
    )
}

/// The interval choices offered in Settings.
///
/// `.custom` carries its own value so the picker and a free-text field can share
/// one representation.
public enum IntervalPreset: Equatable, Hashable, Sendable {
    case seconds10
    case seconds30
    case minutes1
    case minutes20
    case minutes30
    case minutes40
    case minutes45
    case minutes60
    case custom(TimeInterval)

    public var seconds: TimeInterval {
        switch self {
        case .seconds10: return 10
        case .seconds30: return 30
        case .minutes1:  return 60
        case .minutes20: return 20 * 60
        case .minutes30: return 30 * 60
        case .minutes40: return 40 * 60
        case .minutes45: return 45 * 60
        case .minutes60: return 60 * 60
        case .custom(let value): return value
        }
    }

    /// Presets safe to offer for production use.
    public static let standard: [IntervalPreset] = [
        .minutes20, .minutes30, .minutes40, .minutes45, .minutes60,
    ]

    /// Very short intervals, offered only while Test Mode is on.
    public static let testing: [IntervalPreset] = [.seconds10, .seconds30, .minutes1]

    public var displayName: String {
        let s = seconds
        if s < 60 { return "\(Int(s)) seconds" }
        if s < 3600 {
            let m = Int(s / 60)
            return m == 1 ? "1 minute" : "\(m) minutes"
        }
        let h = s / 3600
        return h == 1 ? "1 hour" : String(format: "%.1f hours", h)
    }
}
