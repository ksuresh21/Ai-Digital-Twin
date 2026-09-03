import Foundation

/// One of the alert sounds macOS ships with, or silence.
///
/// Deliberately limited to the built-in set in `/System/Library/Sounds` rather
/// than bundling audio of our own. Those fourteen names are the ones every Mac
/// user has already heard for years, they are already tuned to sit politely
/// under other audio, and shipping none of our own keeps the app a few hundred
/// kilobytes smaller and free of any licensing question about the samples.
///
/// The raw values are the file names, so this enum *is* the lookup key --
/// `AiTwinMac` passes `systemName` straight to `NSSound(named:)`. Nothing here
/// imports AppKit, so the choice stays testable and portable.
public enum AlertSound: String, Codable, CaseIterable, Sendable {
    /// No sound. Distinct from switching sounds off entirely: it lets you
    /// silence one cue -- say, the reminder chime -- while keeping the others.
    case none
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    /// The name macOS knows this sound by, or nil for silence.
    public var systemName: String? {
        self == .none ? nil : rawValue
    }

    public var displayName: String {
        self == .none ? "None" : rawValue
    }
}

/// Which moment a sound is being played for.
public enum SoundCue: Equatable, Sendable {
    /// She has appeared with a reminder — water, eyes or posture.
    case reminder
    /// An eye break's countdown has run out.
    case breakOver
    /// A focus phase ended and the next one began.
    case focusPhase
}

/// The user's sound choices: one master switch and a tone per cue.
///
/// A single switch on top of per-cue tones, rather than three independent
/// toggles, because "make it stop" is the thing you want at 11pm and hunting
/// three checkboxes to get there is a bad answer.
public struct SoundSettings: Codable, Equatable, Sendable {
    /// The master switch. Off means nothing plays, whatever the tones say.
    public var enabled: Bool
    /// Played when a reminder appears.
    public var reminder: AlertSound
    /// Played when the eye break's countdown finishes.
    ///
    /// The most useful of the three by some distance: during a break the screen
    /// is dimmed and you are deliberately looking somewhere else, so a sound is
    /// the *only* way to be told it is over without watching the clock you were
    /// told to stop watching.
    public var breakOver: AlertSound
    /// Played when a focus session or focus break ends.
    public var focusPhase: AlertSound
    /// How loud, 0...1, relative to the system alert volume.
    ///
    /// One level for all three cues rather than one each: the reason to reach
    /// for this is "the chime startles me", which is about the app, not about
    /// which moment produced the sound.
    public var volume: Double

    public init(
        enabled: Bool = true,
        reminder: AlertSound = .tink,
        breakOver: AlertSound = .glass,
        focusPhase: AlertSound = .hero,
        volume: Double = 1
    ) {
        self.enabled = enabled
        self.reminder = reminder
        self.breakOver = breakOver
        self.focusPhase = focusPhase
        self.volume = Self.clamp(volume)
    }

    /// Volume is stored from a slider and read from a settings file that a user
    /// could have edited, so it is clamped rather than trusted. `NSSound`
    /// silently ignores a value outside 0...1, which would look like the sound
    /// feature breaking rather than like a bad number.
    static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 1))
    }

    /// Quiet, distinct defaults. `Tink` is the softest thing in the set, which
    /// is right for the cue that fires most often; `Glass` and `Hero` are
    /// clearly different from it and from each other, so the three moments are
    /// distinguishable without looking at the screen.
    public static let defaults = SoundSettings()

    /// Everything silent, but each cue's tone remembered for when it comes back.
    public static let silent = SoundSettings(enabled: false)

    /// What to actually play for a cue, or nil for silence.
    ///
    /// The one place the master switch and quiet hours are applied. Callers ask
    /// this question and play what comes back; nobody else gets to decide what
    /// "enabled" means.
    ///
    /// Quiet hours is a required argument rather than a defaulted one on
    /// purpose. A default would let a future call site forget it and make noise
    /// at 3am, and that bug would only ever be found at 3am.
    ///
    /// Reminders are already held by the engine during quiet hours, so this is
    /// really about the two cues that can *cross into* the window: a focus
    /// phase started at 21:50 that ends at 22:15, and an eye break accepted at
    /// 21:59 whose countdown runs out at 22:01. The engine never stops those,
    /// because you started them deliberately -- but "stay quiet during set
    /// hours" has to mean quiet, or the setting is lying.
    public func sound(
        for cue: SoundCue,
        quietHours: QuietHours,
        at now: Date,
        calendar: Calendar = .current
    ) -> AlertSound? {
        guard enabled else { return nil }
        guard !quietHours.contains(now, calendar: calendar) else { return nil }
        let choice: AlertSound
        switch cue {
        case .reminder:   choice = reminder
        case .breakOver:  choice = breakOver
        case .focusPhase: choice = focusPhase
        }
        return choice == .none ? nil : choice
    }

    /// Decodes tolerantly, for the same reason `AiTwinSettings` does: a settings
    /// file written before sounds existed must not fail to decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SoundSettings.defaults
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)).flatMap { $0 } ?? fallback.enabled
        volume = Self.clamp((try? container.decodeIfPresent(Double.self, forKey: .volume)).flatMap { $0 } ?? fallback.volume)
        reminder = (try? container.decodeIfPresent(AlertSound.self, forKey: .reminder)).flatMap { $0 } ?? fallback.reminder
        breakOver = (try? container.decodeIfPresent(AlertSound.self, forKey: .breakOver)).flatMap { $0 } ?? fallback.breakOver
        focusPhase = (try? container.decodeIfPresent(AlertSound.self, forKey: .focusPhase)).flatMap { $0 } ?? fallback.focusPhase
    }
}
