import Foundation
import Testing
@testable import AiTwinCore

/// The sound settings: the master switch, the per-cue tones, and the promise
/// that every tone names a file macOS actually has.
@Suite("Sounds")
struct SoundTests {

    // MARK: The master switch

    @Test("each cue plays its own tone")
    func cuesAreIndependent() {
        let sounds = SoundSettings(
            enabled: true, reminder: .tink, breakOver: .glass, focusPhase: .hero
        )
        #expect(sounds.sound(for: .reminder) == .tink)
        #expect(sounds.sound(for: .breakOver) == .glass)
        #expect(sounds.sound(for: .focusPhase) == .hero)
    }

    @Test("the master switch silences every cue, tones and all")
    func masterSwitchWins() {
        var sounds = SoundSettings(
            enabled: true, reminder: .tink, breakOver: .glass, focusPhase: .hero
        )
        sounds.enabled = false
        #expect(sounds.sound(for: .reminder) == nil)
        #expect(sounds.sound(for: .breakOver) == nil)
        #expect(sounds.sound(for: .focusPhase) == nil)
    }

    @Test("switching sounds back on restores the tones you had chosen")
    func tonesSurviveTheSwitch() {
        var sounds = SoundSettings(
            enabled: true, reminder: .submarine, breakOver: .purr, focusPhase: .frog
        )
        sounds.enabled = false
        sounds.enabled = true
        // The point of a master switch over three separate Nones: your choices
        // are still there when you come back.
        #expect(sounds.sound(for: .reminder) == .submarine)
        #expect(sounds.sound(for: .breakOver) == .purr)
        #expect(sounds.sound(for: .focusPhase) == .frog)
    }

    @Test("one cue can be silenced without silencing the rest")
    func noneIsPerCue() {
        let sounds = SoundSettings(
            enabled: true, reminder: .none, breakOver: .glass, focusPhase: .hero
        )
        #expect(sounds.sound(for: .reminder) == nil)
        #expect(sounds.sound(for: .breakOver) == .glass)
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
        let chosen = [defaults.reminder, defaults.breakOver, defaults.focusPhase]
        #expect(Set(chosen).count == 3)
        #expect(!chosen.contains(.none))
        #expect(defaults.enabled)
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
            enabled: false, reminder: .morse, breakOver: .none, focusPhase: .bottle
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: data)
        #expect(decoded.sounds == settings.sounds)
    }

    @Test("a settings file with a sound name we no longer ship falls back")
    func unknownToneFallsBack() throws {
        let json = #"{"sounds":{"enabled":true,"reminder":"Fanfare","breakOver":"Glass","focusPhase":"Hero"}}"#
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(json.utf8))
        // The unreadable field falls back on its own; the readable ones beside
        // it are kept rather than the whole block being thrown away.
        #expect(decoded.sounds.reminder == SoundSettings.defaults.reminder)
        #expect(decoded.sounds.breakOver == .glass)
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
