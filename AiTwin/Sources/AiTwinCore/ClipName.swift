import Foundation

/// The animation clips the app asks for by name.
///
/// The original spec listed `glasses_on` and `glasses_off` as animation states.
/// They were built as a variant layer and then removed: the glasses only ever
/// existed to signal the eye-break reminder, which the dimmed screen and the
/// countdown now do far better, and carrying a second copy of every clip for a
/// cosmetic toggle nobody used was not worth it.
public enum ClipName {
    public static let idle = "idle"
    public static let walk = "walk"
    public static let wave = "wave"
    public static let waterReminder = "drink"
    public static let eyeBreak = "eyebreak"
    public static let sleep = "sleep"
    public static let happy = "happy"
    /// Sitting and reading, for focus sessions. Near-static by design.
    public static let focus = "focus"
    /// A standing stretch, for posture reminders.
    public static let stretch = "stretch"
    /// Worried. Shown after a long stretch with no break, or repeated skips.
    public static let concerned = "concerned"
    /// A bigger celebration than `happy`, for streak milestones.
    public static let cheer = "cheer"
    /// Half-hidden at the screen edge. The pose for idle chatter.
    public static let peek = "peek"
    /// Yawning, for late nights and very long sessions.
    public static let yawn = "yawn"
    /// Sitting idle on a chair. Optional variety.
    public static let sitting = "sitting"

    /// Clips whose absence is worth reporting in Settings.
    ///
    /// The rule is simply "can the app actually show it?". Nagging about art
    /// for a pose that can never appear is noise, and staying quiet about art
    /// the app genuinely needs is worse -- the clip silently falls back to idle
    /// and the behaviour just looks broken.
    ///
    /// `sleep` is deliberately absent. She no longer settles into the sleeping
    /// pose: winding down is two yawns and then she leaves, so the sleep frames
    /// are never drawn. `yawn` is here for exactly that reason -- it is now the
    /// whole of the late-night behaviour rather than a lead-in to it.
    ///
    /// `sitting` is absent too: nothing summons it since the stretch routine
    /// stopped sitting her down first.
    public static let all: [String] = [
        idle, walk, wave, waterReminder, eyeBreak, happy,
        focus, stretch, concerned, cheer, peek, yawn,
    ]

    /// Everything the loader knows how to read, including poses nothing
    /// currently summons. A pack may still ship them and they will load.
    public static let loadable: [String] = all + [sleep, sitting]

}

/// Where a clip's frames live on disk and how they are named.
///
/// One definition per clip means adding an animation is a one-line change here
/// plus a folder of PNGs -- no code in the animation engine changes.
public struct ClipDefinition: Equatable, Sendable {
    public let name: String
    /// Sub-folder inside the character pack.
    public let folder: String
    /// Frame filename prefix, e.g. `walk` for `walk_01.png`.
    public let filePrefix: String
    /// Looping clips repeat forever; one-shot clips hold on their last frame and
    /// report `isFinished`, which is how the state machine knows a wave is over.
    public let loops: Bool

    public init(name: String, folder: String, filePrefix: String, loops: Bool) {
        self.name = name
        self.folder = folder
        self.filePrefix = filePrefix
        self.loops = loops
    }

    /// The clip catalogue for a character pack. Folder names match Docs/ASSETS.md.
    public static let standard: [ClipDefinition] = [
        ClipDefinition(name: ClipName.idle,           folder: "Idle",           filePrefix: "idle",     loops: true),
        ClipDefinition(name: ClipName.walk,           folder: "Walking",        filePrefix: "walk",     loops: true),
        ClipDefinition(name: ClipName.wave,           folder: "Waving",         filePrefix: "wave",     loops: false),
        ClipDefinition(name: ClipName.waterReminder,  folder: "WaterReminder",  filePrefix: "drink",    loops: true),
        ClipDefinition(name: ClipName.eyeBreak,       folder: "EyeBreak",       filePrefix: "eyebreak", loops: true),
        ClipDefinition(name: ClipName.sleep,          folder: "Sleep",          filePrefix: "sleep",    loops: true),
        ClipDefinition(name: ClipName.happy,          folder: "HappyMood",      filePrefix: "happy",    loops: false),
        ClipDefinition(name: ClipName.focus,          folder: "Focus",          filePrefix: "focus",    loops: true),
        ClipDefinition(name: ClipName.stretch,        folder: "Stretch",        filePrefix: "stretch",  loops: true),
        ClipDefinition(name: ClipName.concerned,      folder: "Concerned",      filePrefix: "concerned", loops: true),
        ClipDefinition(name: ClipName.cheer,          folder: "Cheer",          filePrefix: "cheer",    loops: false),
        ClipDefinition(name: ClipName.peek,           folder: "Peek",           filePrefix: "peek",     loops: true),
        ClipDefinition(name: ClipName.yawn,           folder: "Yawn",           filePrefix: "yawn",     loops: false),
        ClipDefinition(name: ClipName.sitting,        folder: "Sitting",        filePrefix: "sitting",  loops: true),
    ]
}
