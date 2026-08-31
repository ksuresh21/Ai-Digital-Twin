import Foundation

/// Everything the user can change at runtime, all of it persisted locally.
///
/// Split from `AiTwinConfiguration` on purpose: the configuration holds
/// build-time constants, this holds the user's choices. The spec's example put
/// intervals in an immutable config struct, but Section 3 also requires changing
/// them from the Settings window, so they belong here.
public struct AiTwinSettings: Codable, Equatable, Sendable {

    // MARK: Reminders
    public var waterEnabled: Bool
    public var eyeBreakEnabled: Bool
    public var waterInterval: TimeInterval
    public var eyeBreakInterval: TimeInterval
    public var snoozeInterval: TimeInterval
    /// Global pause. Survives relaunch on purpose -- a user who paused for a
    /// presentation should not be ambushed by a restart.
    public var remindersPaused: Bool

    // MARK: Screen-time awareness
    /// Stop the countdown while the user is away from the keyboard, so the
    /// eye-break cycle measures actual screen usage.
    public var pauseWhenIdle: Bool
    public var idleThreshold: TimeInterval

    // MARK: Quiet hours
    public var quietHours: QuietHours

    // MARK: Water tracking
    public var dailyWaterGoal: Int

    // MARK: Appearance / placement
    public var corner: ScreenCorner
    public var characterHeight: Double
    public var characterPackName: String
    public var wearsGlasses: Bool

    // MARK: Eye-break session
    /// How long the screen dims for after you accept an eye break.
    public var eyeBreakDuration: TimeInterval
    /// Whether accepting an eye break dims the screen. With this off, the
    /// reminder just goes away when acknowledged.
    public var dimsScreenOnBreak: Bool
    /// How dark the dimming gets, 0...1.
    public var dimOpacity: Double

    // MARK: Appearance of messages
    public var bubbleStyle: BubbleStyle

    // MARK: Personalisation
    /// What the character calls you. Empty means it greets you without a name.
    public var userName: String
    /// Cleared once the welcome/setup has been shown, so it only appears once.
    public var hasCompletedFirstRun: Bool

    // MARK: Behaviour
    public var greetOnLaunch: Bool
    public var greetOnWake: Bool
    public var startAtLogin: Bool
    /// Exposes the very short intervals from `IntervalPreset.testing`.
    public var testModeEnabled: Bool

    /// Version 1 defaults. Note `corner: .bottomLeft`, as specified.
    public static let defaults = AiTwinSettings(
        waterEnabled: true,
        eyeBreakEnabled: true,
        waterInterval: AiTwinConfiguration.production.waterReminderInterval,
        eyeBreakInterval: AiTwinConfiguration.production.eyeBreakInterval,
        snoozeInterval: AiTwinConfiguration.production.snoozeInterval,
        remindersPaused: false,
        pauseWhenIdle: true,
        idleThreshold: AiTwinConfiguration.production.idlePauseThreshold,
        quietHours: .disabled,
        dailyWaterGoal: 8,
        eyeBreakDuration: 60,
        dimsScreenOnBreak: true,
        dimOpacity: 0.5,
        bubbleStyle: .cloud,
        corner: .bottomLeft,
        characterHeight: AiTwinConfiguration.production.characterHeight,
        characterPackName: CharacterPack.defaultPackName,
        wearsGlasses: false,
        userName: "",
        hasCompletedFirstRun: false,
        greetOnLaunch: true,
        greetOnWake: true,
        startAtLogin: false,
        testModeEnabled: false
    )

    /// Decodes tolerantly: any field missing from stored JSON falls back to its
    /// default rather than failing the whole decode.
    ///
    /// Without this, adding a single new setting in a later version would make
    /// every existing user's saved settings undecodable, silently resetting
    /// their character, intervals and corner back to factory values. Settings
    /// are cheap to migrate and expensive to lose.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AiTwinSettings.defaults
        func value<T: Decodable>(_ key: CodingKeys, _ standard: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? standard
        }
        waterEnabled        = value(.waterEnabled, fallback.waterEnabled)
        eyeBreakEnabled     = value(.eyeBreakEnabled, fallback.eyeBreakEnabled)
        waterInterval       = value(.waterInterval, fallback.waterInterval)
        eyeBreakInterval    = value(.eyeBreakInterval, fallback.eyeBreakInterval)
        snoozeInterval      = value(.snoozeInterval, fallback.snoozeInterval)
        remindersPaused     = value(.remindersPaused, fallback.remindersPaused)
        pauseWhenIdle       = value(.pauseWhenIdle, fallback.pauseWhenIdle)
        idleThreshold       = value(.idleThreshold, fallback.idleThreshold)
        quietHours          = value(.quietHours, fallback.quietHours)
        dailyWaterGoal      = value(.dailyWaterGoal, fallback.dailyWaterGoal)
        eyeBreakDuration    = value(.eyeBreakDuration, fallback.eyeBreakDuration)
        dimsScreenOnBreak   = value(.dimsScreenOnBreak, fallback.dimsScreenOnBreak)
        dimOpacity          = value(.dimOpacity, fallback.dimOpacity)
        bubbleStyle         = value(.bubbleStyle, fallback.bubbleStyle)
        corner              = value(.corner, fallback.corner)
        characterHeight     = value(.characterHeight, fallback.characterHeight)
        characterPackName   = value(.characterPackName, fallback.characterPackName)
        wearsGlasses        = value(.wearsGlasses, fallback.wearsGlasses)
        userName            = value(.userName, fallback.userName)
        hasCompletedFirstRun = value(.hasCompletedFirstRun, fallback.hasCompletedFirstRun)
        greetOnLaunch       = value(.greetOnLaunch, fallback.greetOnLaunch)
        greetOnWake         = value(.greetOnWake, fallback.greetOnWake)
        startAtLogin        = value(.startAtLogin, fallback.startAtLogin)
        testModeEnabled     = value(.testModeEnabled, fallback.testModeEnabled)
    }

    /// Explicit memberwise initialiser, which the custom decoder above suppresses.
    public init(
        waterEnabled: Bool, eyeBreakEnabled: Bool,
        waterInterval: TimeInterval, eyeBreakInterval: TimeInterval,
        snoozeInterval: TimeInterval, remindersPaused: Bool,
        pauseWhenIdle: Bool, idleThreshold: TimeInterval,
        quietHours: QuietHours, dailyWaterGoal: Int,
        eyeBreakDuration: TimeInterval, dimsScreenOnBreak: Bool, dimOpacity: Double,
        bubbleStyle: BubbleStyle,
        corner: ScreenCorner, characterHeight: Double,
        characterPackName: String, wearsGlasses: Bool,
        userName: String, hasCompletedFirstRun: Bool,
        greetOnLaunch: Bool, greetOnWake: Bool,
        startAtLogin: Bool, testModeEnabled: Bool
    ) {
        self.waterEnabled = waterEnabled
        self.eyeBreakEnabled = eyeBreakEnabled
        self.waterInterval = waterInterval
        self.eyeBreakInterval = eyeBreakInterval
        self.snoozeInterval = snoozeInterval
        self.remindersPaused = remindersPaused
        self.pauseWhenIdle = pauseWhenIdle
        self.idleThreshold = idleThreshold
        self.quietHours = quietHours
        self.dailyWaterGoal = dailyWaterGoal
        self.eyeBreakDuration = eyeBreakDuration
        self.dimsScreenOnBreak = dimsScreenOnBreak
        self.dimOpacity = dimOpacity
        self.bubbleStyle = bubbleStyle
        self.corner = corner
        self.characterHeight = characterHeight
        self.characterPackName = characterPackName
        self.wearsGlasses = wearsGlasses
        self.userName = userName
        self.hasCompletedFirstRun = hasCompletedFirstRun
        self.greetOnLaunch = greetOnLaunch
        self.greetOnWake = greetOnWake
        self.startAtLogin = startAtLogin
        self.testModeEnabled = testModeEnabled
    }

    public func interval(for kind: ReminderKind) -> TimeInterval {
        switch kind {
        case .water:    return waterInterval
        case .eyeBreak: return eyeBreakInterval
        }
    }

    public func isEnabled(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .water:    return waterEnabled
        case .eyeBreak: return eyeBreakEnabled
        }
    }
}

/// Where settings are read from and written to.
public protocol SettingsStoring: AnyObject {
    func load() -> AiTwinSettings
    func save(_ settings: AiTwinSettings)
}

/// Test double, and the fallback if persistence is ever unavailable.
public final class InMemorySettingsStore: SettingsStoring {
    private var settings: AiTwinSettings
    public init(_ settings: AiTwinSettings = .defaults) {
        self.settings = settings
    }
    public func load() -> AiTwinSettings { settings }
    public func save(_ settings: AiTwinSettings) { self.settings = settings }
}

/// Real persistence. JSON in UserDefaults keeps the whole struct in one key, so
/// adding a field later cannot leave a half-migrated set of loose keys behind.
public final class UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.aitwin.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AiTwinSettings {
        guard let data = defaults.data(forKey: key) else { return .defaults }
        // A settings file written by a newer version, or corrupted on disk,
        // must not stop the app from launching -- fall back to defaults.
        return (try? JSONDecoder().decode(AiTwinSettings.self, from: data)) ?? .defaults
    }

    public func save(_ settings: AiTwinSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
