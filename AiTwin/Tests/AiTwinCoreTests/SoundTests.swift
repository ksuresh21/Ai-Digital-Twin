import Foundation
import Testing
@testable import AiTwinCore

/// The sound settings: the master switch, the per-cue tones, and the promise
/// that every tone names a file macOS actually has.
@Suite("Sounds")
struct SoundTests {

    /// Noon, with quiet hours off — "no reason to be silent" for the tests that
    /// are about something other than silence.
    private func audible(_ sounds: SoundSettings, _ cue: SoundCue) -> AlertSound? {
        sounds.sound(for: cue, quietHours: .disabled, at: Date(), calendar: .testUTC)
    }

    // MARK: The master switch

    @Test("each cue plays its own tone")
    func cuesAreIndependent() {
        let sounds = SoundSettings(
            enabled: true, acknowledged: .tink, breakOver: .glass, focusPhase: .hero
        )
        #expect(audible(sounds, .acknowledged) == .tink)
        #expect(audible(sounds, .breakOver) == .glass)
        #expect(audible(sounds, .focusPhase) == .hero)
    }

    @Test("the master switch silences every cue, tones and all")
    func masterSwitchWins() {
        var sounds = SoundSettings(
            enabled: true, acknowledged: .tink, breakOver: .glass, focusPhase: .hero
        )
        sounds.enabled = false
        #expect(audible(sounds, .acknowledged) == nil)
        #expect(audible(sounds, .breakOver) == nil)
        #expect(audible(sounds, .focusPhase) == nil)
    }

    @Test("switching sounds back on restores the tones you had chosen")
    func tonesSurviveTheSwitch() {
        var sounds = SoundSettings(
            enabled: true, acknowledged: .submarine, breakOver: .purr, focusPhase: .frog
        )
        sounds.enabled = false
        sounds.enabled = true
        // The point of a master switch over three separate Nones: your choices
        // are still there when you come back.
        #expect(audible(sounds, .acknowledged) == .submarine)
        #expect(audible(sounds, .breakOver) == .purr)
        #expect(audible(sounds, .focusPhase) == .frog)
    }

    @Test("one cue can be silenced without silencing the rest")
    func noneIsPerCue() {
        let sounds = SoundSettings(
            enabled: true, acknowledged: .none, breakOver: .glass, focusPhase: .hero
        )
        #expect(audible(sounds, .acknowledged) == nil)
        #expect(audible(sounds, .breakOver) == .glass)
    }

    // MARK: The tones themselves

    @Test("every tone but None names a sound this Mac actually has")
    func everyToneExists() {
        // A typo in a raw value would otherwise show up as one silent cue that
        // nobody notices for months. The names are file names in a directory
        // that has been stable since Mac OS X, so checking them is fair.
        for sound in AlertSound.allCases where sound != .none {
            let name = try! #require(sound.systemName)
            let path = "/System/Library/Sounds/\(name).aiff"
            #expect(FileManager.default.fileExists(atPath: path), "missing: \(path)")
        }
    }

    @Test("None is silence, and says so")
    func noneIsSilent() {
        #expect(AlertSound.none.systemName == nil)
        #expect(AlertSound.none.displayName == "None")
    }

    @Test("the three defaults are distinct, so the cues are told apart by ear")
    func defaultsAreDistinguishable() {
        let defaults = SoundSettings.defaults
        let chosen = [defaults.acknowledged, defaults.breakOver, defaults.focusPhase]
        #expect(Set(chosen).count == 3)
        #expect(!chosen.contains(.none))
        #expect(defaults.enabled)
    }

    // MARK: Quiet hours

    /// A date at a given hour, in the fixed UTC calendar the tests use.
    private func at(hour: Int, minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2023; parts.month = 11; parts.day = 14
        parts.hour = hour; parts.minute = minute
        return Calendar.testUTC.date(from: parts)!
    }

    private func inQuietHours(_ sounds: SoundSettings, _ cue: SoundCue, at date: Date) -> AlertSound? {
        sounds.sound(
            for: cue,
            quietHours: QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60),
            at: date,
            calendar: .testUTC
        )
    }

    @Test("quiet hours silences a focus phase that ran into the window")
    func focusCrossingIntoQuietHours() {
        // The case that motivated this: the engine holds *reminders* during
        // quiet hours, but a focus session you started at 21:50 is not held --
        // you started it deliberately. It still must not chime at 22:15.
        let sounds = SoundSettings.defaults
        #expect(inQuietHours(sounds, .focusPhase, at: at(hour: 21, minute: 50)) == .hero)
        #expect(inQuietHours(sounds, .focusPhase, at: at(hour: 22, minute: 15)) == nil)
    }

    @Test("quiet hours silences an eye break whose countdown ends inside it")
    func breakCrossingIntoQuietHours() {
        let sounds = SoundSettings.defaults
        #expect(inQuietHours(sounds, .breakOver, at: at(hour: 21, minute: 59)) == .glass)
        #expect(inQuietHours(sounds, .breakOver, at: at(hour: 22, minute: 1)) == nil)
    }

    @Test("the window that crosses midnight is silent at both ends of it")
    func quietHoursAcrossMidnight() {
        let sounds = SoundSettings.defaults
        // 22:00 -> 07:00 is the default and the interesting shape: a naive
        // start <= t < end would leave the whole night audible.
        #expect(inQuietHours(sounds, .acknowledged, at: at(hour: 23)) == nil)
        #expect(inQuietHours(sounds, .acknowledged, at: at(hour: 3)) == nil)
        #expect(inQuietHours(sounds, .acknowledged, at: at(hour: 6, minute: 59)) == nil)
        #expect(inQuietHours(sounds, .acknowledged, at: at(hour: 7)) == .tink)
    }

    @Test("quiet hours switched off silences nothing")
    func quietHoursDisabled() {
        let sounds = SoundSettings.defaults
        let off = QuietHours(isEnabled: false, startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(sounds.sound(for: .acknowledged, quietHours: off, at: at(hour: 23), calendar: .testUTC) == .tink)
    }

    // MARK: Volume

    @Test("volume defaults to full, and is a level not a switch")
    func volumeDefault() {
        #expect(SoundSettings.defaults.volume == 1)
    }

    @Test("a volume outside 0...1 is clamped rather than trusted")
    func volumeClamped() {
        // NSSound silently ignores a value out of range, which would look like
        // the whole sound feature broke rather than like one bad number.
        #expect(SoundSettings(volume: 4).volume == 1)
        #expect(SoundSettings(volume: -2).volume == 0)
        #expect(SoundSettings(volume: .nan).volume == 1)
        #expect(SoundSettings(volume: 0.4).volume == 0.4)
    }

    @Test("a hand-edited settings file cannot smuggle in a bad volume")
    func volumeClampedOnDecode() throws {
        let json = #"{"sounds":{"enabled":true,"acknowledged":"Tink","breakOver":"Glass","focusPhase":"Hero","volume":9}}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        #expect(decoded.sounds.volume == 1)
    }

    @Test("silence is a volume of zero, and stays a valid setting")
    func volumeZero() {
        var sounds = SoundSettings.defaults
        sounds.volume = 0
        // Still "enabled" -- the cue resolves to a tone, it is just inaudible.
        // Turning the app silent this way is the user's business, not a bug.
        #expect(audible(sounds, .acknowledged) == .tink)
        #expect(sounds.volume == 0)
    }

    // MARK: The retired arrival cue

    @Test("a tone chosen under the old name is carried over, not reset")
    func legacyReminderKeyIsRead() throws {
        // The field used to be called `reminder` and played when she walked in.
        // It now plays when you press the button. Same tone, later moment — so
        // someone who had chosen Submarine keeps Submarine.
        let json = #"{"sounds":{"enabled":true,"reminder":"Submarine","breakOver":"Glass","focusPhase":"Hero","volume":1}}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        #expect(decoded.sounds.acknowledged == .submarine)
    }

    @Test("the new name wins if a file somehow has both")
    func newKeyBeatsLegacy() throws {
        let json = #"{"sounds":{"acknowledged":"Frog","reminder":"Submarine"}}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        #expect(decoded.sounds.acknowledged == .frog)
    }

    @Test("the retired name is read but never written back")
    func legacyKeyIsNotRewritten() throws {
        var sounds = SoundSettings.defaults
        sounds.acknowledged = .frog
        let data = try JSONEncoder().encode(sounds)
        let text = String(decoding: data, as: UTF8.self)
        // Otherwise every save would carry a second, stale copy of the field
        // forward forever.
        #expect(text.contains("acknowledged"))
        #expect(!text.contains("\"reminder\""))
    }

    @Test("every cue is an ending — nothing announces her arrival")
    func everyCueIsAnEnding() {
        // The rule this whole rename exists to enforce. If a fourth cue is ever
        // added for something that fires on her walking in, this is where the
        // argument should happen.
        let sounds = SoundSettings.defaults
        let cues: [SoundCue] = [.acknowledged, .breakOver, .focusPhase]
        #expect(cues.allSatisfy { audible(sounds, $0) != nil })
    }

    // MARK: Persistence

    @Test("settings saved before sounds existed still load")
    func oldSettingsDecode() throws {
        // The real risk of adding a field: an existing user's file has no
        // "sounds" key at all, and a strict decode would reset their character,
        // corner and intervals along with it.
        let json = #"{"waterEnabled":true,"characterHeight":200,"userName":"Suresh"}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        #expect(decoded.sounds == SoundSettings.defaults)
        #expect(decoded.userName == "Suresh")
        #expect(decoded.characterHeight == 200)
    }

    @Test("sound choices survive a save and load")
    func roundTrips() throws {
        var settings = AiTwinSettings.defaults
        settings.sounds = SoundSettings(
            enabled: false, acknowledged: .morse, breakOver: .none, focusPhase: .bottle, volume: 0.35
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: data)
        #expect(decoded.sounds == settings.sounds)
    }

    @Test("a settings file with a sound name we no longer ship falls back")
    func unknownToneFallsBack() throws {
        let json = #"{"sounds":{"enabled":true,"acknowledged":"Fanfare","breakOver":"Glass","focusPhase":"Hero"}}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        // The unreadable field falls back on its own; the readable ones beside
        // it are kept rather than the whole block being thrown away.
        #expect(decoded.sounds.acknowledged == SoundSettings.defaults.acknowledged)
        #expect(decoded.sounds.breakOver == .glass)
        #expect(decoded.sounds.volume == SoundSettings.defaults.volume)
    }
}

/// The stretch reminder, which had no way into it from Settings until now.
@Suite("Stretch reminder")
struct StretchSettingsTests {

    @Test("stretch is on by default, every hour")
    func defaults() {
        let settings = AiTwinSettings.defaults
        #expect(settings.isEnabled(.stretch))
        #expect(settings.interval(for: .stretch) == 60 * 60)
    }

    @Test("the hourly default is one of the intervals the picker offers")
    func defaultIntervalIsSelectable() {
        // Otherwise the Settings picker opens with nothing selected, or with a
        // "Custom" row for a value that is not custom at all.
        let offered = IntervalPreset.standard.map(\.seconds)
        #expect(offered.contains(AiTwinSettings.defaults.stretchInterval))
    }

    @Test("turning stretch off leaves water and eyes alone")
    func togglesIndependently() {
        var settings = AiTwinSettings.defaults
        settings.stretchEnabled = false
        #expect(!settings.isEnabled(.stretch))
        #expect(settings.isEnabled(.water))
        #expect(settings.isEnabled(.eyeBreak))
    }

    @Test("a changed stretch interval is what the engine schedules on")
    func intervalIsHonoured() {
        var settings = AiTwinSettings.defaults
        settings.stretchInterval = 30 * 60
        #expect(settings.interval(for: .stretch) == 30 * 60)
    }
}

/// Which focus phase changes are an *ending* worth chiming for.
@Suite("Focus phase endings")
struct FocusPhaseEndingTests {

    private func session(_ phase: FocusSession.Phase, completed: Int) -> FocusSession {
        FocusSession(phase: phase, duration: 60, startedAt: Date(), completedSessions: completed)
    }

    @Test("starting the very first session announces nothing")
    func firstStartIsSilent() {
        // The bug this guards: chiming on every `onPhaseChange` means pressing
        // Start Focus plays the "phase over" sound before any work happens.
        #expect(session(.working, completed: 0).endsAPreviousPhase == false)
    }

    @Test("reaching a break means the work phase ended")
    func workEnding() {
        #expect(session(.shortBreak, completed: 1).endsAPreviousPhase)
        #expect(session(.longBreak, completed: 4).endsAPreviousPhase)
    }

    @Test("going back to work means the break ended")
    func breakEnding() {
        #expect(session(.working, completed: 1).endsAPreviousPhase)
    }

    @Test("every phase of a full cycle chimes exactly once, except the opening")
    func wholeCycle() {
        let controller = FocusController(settings: .defaults, clock: SystemClock())
        var announced: [FocusSession.Phase] = []
        controller.onPhaseChange = { session in
            guard let session, session.endsAPreviousPhase else { return }
            announced.append(session.phase)
        }
        controller.start()
        controller.skip()   // work done -> short break
        controller.skip()   // break done -> work
        controller.skip()   // work done -> short break
        #expect(announced == [.shortBreak, .working, .shortBreak])
    }

    @Test("stopping a session by hand chimes nothing")
    func manualStopIsSilent() {
        let controller = FocusController(settings: .defaults, clock: SystemClock())
        controller.start()
        var announced = 0
        controller.onPhaseChange = { session in
            guard let session, session.endsAPreviousPhase else { return }
            announced += 1
        }
        controller.stop()
        // You ended it; you know. A chime here would be the app congratulating
        // you for pressing Stop.
        #expect(announced == 0)
    }
}
