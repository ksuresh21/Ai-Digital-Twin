import Foundation
import Testing
@testable import AiTwinCore

@Suite("Character state machine")
struct CharacterStateMachineTests {

    @Test("the character starts off screen")
    func startsHidden() {
        #expect(CharacterStateMachine().state == .hidden)
    }

    @Test("a greeting pops the character into place rather than walking her in")
    func summonForGreeting() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        #expect(machine.state == .appearing(.greeting))
        // She materialises at the corner; the window does not travel.
        #expect(machine.state.isWalking == false)
    }

    @Test("arriving after a greeting summons the wave")
    func greetingSequence() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .greeting)
        #expect(machine.state.clipName == ClipName.wave)
    }

    @Test("the wave finishing settles into idle")
    func waveSettlesToIdle() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        #expect(machine.state == .idle)
        #expect(machine.state.clipName == ClipName.idle)
    }

    @Test("a water reminder walks in and shows the drinking animation")
    func waterReminderSequence() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .entering(.reminder(.water)))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .reminding(.water))
        #expect(machine.state.clipName == ClipName.waterReminder)
    }

    @Test("an eye break uses its own clip")
    func eyeBreakClip() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.eyeBreak)))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state.clipName == ClipName.eyeBreak)
    }

    @Test("dismissing a reminder sends the character away")
    func dismissLeaves() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.water)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.reminderResolved)
        #expect(machine.state == .leaving)
        #expect(machine.state.clipName == ClipName.walk)
        #expect(machine.state.isWalking)
    }

    @Test("the full launch-to-idle-to-reminder-to-hidden loop")
    func fullCycle() {
        // The integration path from Section 10 of the spec, at state level.
        let machine = CharacterStateMachine()
        var seen: [CharacterState] = []
        machine.onStateChange = { seen.append($0) }

        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        machine.handle(.restTimeout)
        machine.handle(.exitedScreen)
        machine.handle(.summon(.reminder(.eyeBreak)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.reminderResolved)
        machine.handle(.exitedScreen)

        #expect(seen == [
            .appearing(.greeting),
            .greeting,
            .idle,
            .leaving,
            .hidden,
            .entering(.reminder(.eyeBreak)),
            .reminding(.eyeBreak),
            .leaving,
            .hidden,
        ])
    }

    @Test("a reminder while already on screen does not re-walk from off screen")
    func reminderWhileIdle() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }

    @Test("a reminder while walking away turns the character around")
    func reminderWhileLeaving() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.water)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.reminderResolved)
        machine.handle(.summon(.reminder(.eyeBreak)))
        #expect(machine.state == .entering(.reminder(.eyeBreak)))
    }

    @Test("reset hides the character from any state")
    func resetAlwaysHides() {
        for event: CharacterEvent in [.summon(.greeting), .arrivedAtCorner, .animationFinished] {
            let machine = CharacterStateMachine()
            machine.handle(event)
            machine.handle(.reset)
            #expect(machine.state == .hidden)
        }
    }

    @Test("unexpected events are ignored rather than crashing")
    func ignoresUnexpectedEvents() {
        // A desktop pet receiving a stray event should do nothing at all.
        let machine = CharacterStateMachine()
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        machine.handle(.reminderResolved)
        machine.handle(.exitedScreen)
        #expect(machine.state == .hidden)
    }

    @Test("no callback fires when a transition changes nothing")
    func noCallbackWithoutChange() {
        let machine = CharacterStateMachine()
        var changes = 0
        machine.onStateChange = { _ in changes += 1 }
        machine.handle(.arrivedAtCorner)     // illegal from hidden
        #expect(changes == 0)
    }

    @Test("only the walking states move the window")
    func isWalkingIsAccurate() {
        #expect(CharacterState.entering(.greeting).isWalking)
        #expect(CharacterState.leaving.isWalking)
        #expect(CharacterState.idle.isWalking == false)
        #expect(CharacterState.reminding(.water).isWalking == false)
        #expect(CharacterState.hidden.isVisible == false)
        #expect(CharacterState.idle.isVisible)
    }
}

@Suite("Settings and configuration")
struct SettingsTests {

    @Test("Version 1 defaults to the bottom-left corner")
    func defaultCornerIsBottomLeft() {
        #expect(AiTwinSettings.defaults.corner == .bottomLeft)
    }

    @Test("the production eye-break interval is 40 minutes")
    func productionEyeBreak() {
        #expect(AiTwinConfiguration.production.eyeBreakInterval == 40 * 60)
        #expect(AiTwinSettings.defaults.eyeBreakInterval == 40 * 60)
    }

    @Test("the testing configuration uses the short intervals from the spec")
    func testingConfiguration() {
        #expect(AiTwinConfiguration.testing.waterReminderInterval == 30)
        #expect(AiTwinConfiguration.testing.eyeBreakInterval == 60)
    }

    @Test("interval presets convert to the right number of seconds")
    func presetSeconds() {
        #expect(IntervalPreset.seconds10.seconds == 10)
        #expect(IntervalPreset.minutes40.seconds == 2400)
        #expect(IntervalPreset.custom(90).seconds == 90)
    }

    @Test("preset names read correctly")
    func presetNames() {
        #expect(IntervalPreset.seconds30.displayName == "30 seconds")
        #expect(IntervalPreset.minutes1.displayName == "1 minute")
        #expect(IntervalPreset.minutes40.displayName == "40 minutes")
        #expect(IntervalPreset.minutes60.displayName == "1 hour")
    }

    @Test("settings survive a save and load round trip")
    func roundTrip() {
        let store = InMemorySettingsStore()
        var settings = AiTwinSettings.defaults
        settings.corner = .topRight
        settings.eyeBreakInterval = 10
        settings.quietHours = QuietHours(isEnabled: true, startMinutes: 60, endMinutes: 120)
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test("settings encode and decode as JSON")
    func codable() throws {
        var settings = AiTwinSettings.defaults
        settings.characterPackName = "MyCharacter"
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AiTwinSettings.self, from: data) == settings)
    }

    @Test("corrupted stored settings fall back to defaults instead of failing to launch")
    func corruptedSettingsFallBack() {
        let defaults = UserDefaults(suiteName: "com.aitwin.tests.corrupt")!
        defaults.removePersistentDomain(forName: "com.aitwin.tests.corrupt")
        defaults.set(Data("not json".utf8), forKey: "test.key")
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "test.key")
        #expect(store.load() == .defaults)
    }

    @Test("greetings match the time of day")
    func greetings() {
        let calendar = Calendar.testUTC
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func greeting(atHour hour: Int) -> String {
            MessageCatalog.greeting(for: midnight.addingTimeInterval(TimeInterval(hour * 3600)), calendar: calendar)
        }
        #expect(greeting(atHour: 8).contains("morning"))
        #expect(greeting(atHour: 14).contains("afternoon"))
        #expect(greeting(atHour: 19).contains("evening"))
        #expect(greeting(atHour: 3).contains("Still up"))
    }
}

@Suite("Celebration and rendering style")
struct CelebrationTests {

    @Test("reaching the goal summons the character to celebrate")
    func celebrationSummons() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.celebration))
        #expect(machine.state == .appearing(.celebration))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .celebrating)
        #expect(machine.state.clipName == ClipName.happy)
    }

    @Test("celebrating settles back to idle when the animation ends")
    func celebrationSettles() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.celebration))
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        #expect(machine.state == .idle)
    }

    @Test("celebrating while already on screen skips the walk-in")
    func celebrationWhileIdle() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        machine.handle(.animationFinished)
        machine.handle(.summon(.celebration))
        #expect(machine.state == .celebrating)
    }

    @Test("a reminder interrupts a celebration")
    func reminderBeatsCelebration() {
        // The reminder is the app's job; the confetti is not.
        let machine = CharacterStateMachine()
        machine.handle(.summon(.celebration))
        machine.handle(.arrivedAtCorner)
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .reminding(.water))
    }

    @Test("a celebration eventually walks off screen")
    func celebrationLeaves() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.celebration))
        machine.handle(.arrivedAtCorner)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
    }

    @Test("small frames are drawn as pixel art")
    func pixelArtDetection() {
        // The bundled Default pack is authored at 64px.
        #expect(RenderingStyle.forSource(pixelHeight: 32) == .pixelArt)
        #expect(RenderingStyle.forSource(pixelHeight: 64) == .pixelArt)
        #expect(RenderingStyle.forSource(pixelHeight: 128) == .pixelArt)
    }

    @Test("large frames are drawn smoothly")
    func smoothDetection() {
        // Artwork from an image model, normalised to 512px, is scaled DOWN --
        // nearest-neighbour would make hair and outlines crawl.
        #expect(RenderingStyle.forSource(pixelHeight: 512) == .smooth)
        #expect(RenderingStyle.forSource(pixelHeight: 900) == .smooth)
    }

    @Test("the happy clip is part of the standard catalogue")
    func happyClipIsDefined() {
        #expect(ClipDefinition.standard.contains { $0.name == ClipName.happy })
        #expect(ClipName.all.contains(ClipName.happy))
        let happy = ClipDefinition.standard.first { $0.name == ClipName.happy }
        #expect(happy?.folder == "HappyMood")
        // One-shot: the character cheers once, it does not cheer forever.
        #expect(happy?.loops == false)
    }
}

@Suite("Greetings and personalisation")
struct GreetingTests {

    private let calendar = Calendar.testUTC
    private func date(hour: Int) -> Date {
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return midnight.addingTimeInterval(TimeInterval(hour * 3600))
    }

    @Test("the time of day is classified correctly")
    func timeOfDay() {
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 8), calendar: calendar) == .morning)
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 14), calendar: calendar) == .afternoon)
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 19), calendar: calendar) == .evening)
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 2), calendar: calendar) == .lateNight)
        // Boundaries
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 5), calendar: calendar) == .morning)
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 12), calendar: calendar) == .afternoon)
        #expect(MessageCatalog.TimeOfDay.at(date(hour: 22), calendar: calendar) == .lateNight)
    }

    @Test("a greeting with no name reads naturally")
    func greetingWithoutName() {
        let catalog = MessageCatalog(randomSource: { 0 })
        let greeting = catalog.nextGreeting(for: date(hour: 8), name: "", calendar: calendar)
        #expect(greeting.contains("morning"))
        // No stray comma or placeholder left behind.
        #expect(!greeting.contains("{"))
        #expect(!greeting.contains(" ,"))
    }

    @Test("a greeting uses the name when one is set")
    func greetingWithName() {
        let catalog = MessageCatalog(randomSource: { 0 })
        let greeting = catalog.nextGreeting(for: date(hour: 8), name: "Suresh", calendar: calendar)
        #expect(greeting.contains("Suresh"))
        #expect(!greeting.contains("{"))
    }

    @Test("only the first name is used")
    func usesFirstNameOnly() {
        // Entering a full name should not produce "Good morning, Suresh Kumar!".
        #expect(MessageCatalog.fill("{first}", name: "Suresh Kumar") == "Suresh")
        #expect(MessageCatalog.fill("Hi{name}!", name: "Suresh Kumar") == "Hi, Suresh!")
    }

    @Test("whitespace-only names are treated as no name")
    func blankNameIgnored() {
        #expect(MessageCatalog.fill("Hi{name}!", name: "   ") == "Hi!")
        #expect(MessageCatalog.fill("Hi{name}!", name: "") == "Hi!")
    }

    @Test("wake greetings are personalised too")
    func wakeGreeting() {
        let catalog = MessageCatalog(randomSource: { 0 })
        let greeting = catalog.nextWakeGreeting(for: date(hour: 14), name: "Suresh", calendar: calendar)
        #expect(greeting.contains("Suresh"))
        #expect(!greeting.contains("{"))
    }

    @Test("settings saved by an older version still load")
    func settingsForwardCompatible() throws {
        // A payload from before userName existed must not reset everything.
        let legacy = """
        {"waterEnabled":true,"eyeBreakEnabled":true,"waterInterval":30,
         "eyeBreakInterval":60,"snoozeInterval":10,"remindersPaused":false,
         "pauseWhenIdle":false,"idleThreshold":300,
         "quietHours":{"isEnabled":false,"startMinutes":1320,"endMinutes":420},
         "dailyWaterGoal":2,"corner":"bottomLeft","characterHeight":192,
         "characterPackName":"Nish","wearsGlasses":false,"greetOnLaunch":true,
         "greetOnWake":true,"startAtLogin":false,"testModeEnabled":true}
        """
        let decoded = try JSONDecoder().decode(AiTwinSettings.self, from: Data(legacy.utf8))
        #expect(decoded.characterPackName == "Nish")   // preserved, not reset
        #expect(decoded.characterHeight == 192)
        #expect(decoded.userName == "")                // new field defaulted
        #expect(decoded.hasCompletedFirstRun == false)
    }
}

@Suite("Character palette")
struct PaletteTests {

    @Test("luminance decides readable text colour")
    func luminance() {
        #expect(PaletteColor(hex: 0xFFFFFF).luminance > 0.9)
        #expect(PaletteColor(hex: 0x000000).luminance < 0.1)
        // Nish's warm tan is light, so text on it must be dark.
        let tan = CharacterPalette.around(accent: PaletteColor(hex: 0xF0B478))
        #expect(tan.accentForeground == tan.ink)
        // A dark accent flips the text to white.
        let navy = CharacterPalette.around(accent: PaletteColor(hex: 0x213A6B))
        #expect(navy.accentForeground.luminance > 0.9)
    }

    @Test("saturation separates colour from linework")
    func saturation() {
        #expect(PaletteColor(hex: 0x808080).saturation == 0)
        #expect(PaletteColor(hex: 0xF0B478).saturation > 0.4)
    }

    @Test("the accent picker ignores greys, black and white")
    func picksColourNotLinework() {
        // Mostly outline and paper, with a small warm area -- the warm area wins.
        var samples = Array(repeating: PaletteColor(hex: 0x000000), count: 400)
        samples += Array(repeating: PaletteColor(hex: 0xFFFFFF), count: 300)
        samples += Array(repeating: PaletteColor(hex: 0x808080), count: 200)
        samples += Array(repeating: PaletteColor(hex: 0xF0B478), count: 60)
        let accent = AccentPicker.pick(from: samples)
        #expect(accent != nil)
        #expect(accent!.saturation >= AccentPicker.minimumSaturation)
        #expect(accent!.red > accent!.blue)   // warm, as expected
    }

    @Test("an image with no colourful area yields no accent")
    func noAccentFromGreyscale() {
        let greys = [0x000000, 0x333333, 0x808080, 0xCCCCCC, 0xFFFFFF]
            .flatMap { hex in Array(repeating: PaletteColor(hex: UInt32(hex)), count: 100) }
        #expect(AccentPicker.pick(from: greys) == nil)
    }

    @Test("no samples yields no accent rather than a crash")
    func emptySamples() {
        #expect(AccentPicker.pick(from: []) == nil)
    }

    @Test("near-identical shades are counted together")
    func shadesGroup() {
        // Four barely-different tans should beat one large flat blue block.
        var samples: [PaletteColor] = []
        for hex in [0xF0B478, 0xF1B579, 0xEFB377, 0xF0B57A] {
            samples += Array(repeating: PaletteColor(hex: UInt32(hex)), count: 40)
        }
        samples += Array(repeating: PaletteColor(hex: 0x3355CC), count: 120)
        let accent = AccentPicker.pick(from: samples)
        #expect(accent != nil)
        #expect(accent!.red > accent!.blue)
    }

    @Test("darkened and lightened stay in range")
    func clamping() {
        let colour = PaletteColor(hex: 0xF0B478)
        #expect(colour.darkened(by: 2).luminance == 0)
        // Luma weights sum to 1.0 only within float tolerance.
        #expect(abs(colour.lightened(by: 2).luminance - 1) < 1e-9)
        #expect(colour.darkened(by: -1) == colour)
    }
}

@Suite("Message pools")
struct MessagePoolTests {

    @Test("every pool offers ten lines")
    func tenPerPool() {
        for pool in MessageCatalog.allPools {
            #expect(pool.templates.count == 10, "\(pool.key) has \(pool.templates.count)")
        }
    }

    @Test("every pool has lines that work without a name")
    func poolsSurviveWithoutName() {
        // If a pool were made entirely of {first} lines, a user with no name set
        // would get the generic fallback forever.
        for pool in MessageCatalog.allPools {
            let usable = MessageCatalog.usable(pool.templates, hasName: false)
            #expect(usable.count >= 4, "\(pool.key) only has \(usable.count) name-free lines")
        }
    }

    @Test("every pool personalises some of the time")
    func poolsUseTheName() {
        for pool in MessageCatalog.allPools {
            let personal = pool.templates.filter { $0.contains("{first}") || $0.contains("{name}") }
            #expect(personal.count >= 3, "\(pool.key) rarely uses the name")
        }
    }

    @Test("no template leaves a token behind once filled")
    func templatesExpandCleanly() {
        for pool in MessageCatalog.allPools {
            for template in MessageCatalog.usable(pool.templates, hasName: false) {
                let filled = MessageCatalog.fill(template, name: "")
                #expect(!filled.contains("{"))
                #expect(!filled.contains(" ,"))
                #expect(!filled.hasPrefix(","))
            }
            for template in pool.templates {
                let filled = MessageCatalog.fill(template, name: "Suresh")
                #expect(!filled.contains("{"))
            }
        }
    }

    @Test("lines needing a name are dropped when there is none")
    func namedLinesDropped() {
        let usable = MessageCatalog.usable(["Hi {first}!", "Hello{name}"], hasName: false)
        #expect(usable == ["Hello{name}"])
    }

    @Test("messages rotate through the whole pool before repeating")
    func rotatesFully() {
        let catalog = MessageCatalog(randomSource: { 0 })
        var seen: Set<String> = []
        for _ in 0..<10 { seen.insert(catalog.nextMessage(for: .water, name: "Suresh")) }
        #expect(seen.count == 10)
    }

    @Test("each moment has its own rotation")
    func poolsAreIndependent() {
        // Drawing water lines must not use up the eye-break rotation.
        let catalog = MessageCatalog(randomSource: { 0 })
        for _ in 0..<10 { _ = catalog.nextMessage(for: .water, name: "") }
        var seen: Set<String> = []
        for _ in 0..<6 { seen.insert(catalog.nextMessage(for: .eyeBreak, name: "")) }
        #expect(seen.count == 6)
    }

    @Test("break and goal moments have their own lines")
    func breakAndGoalPools() {
        let catalog = MessageCatalog(randomSource: { 0 })
        #expect(!catalog.nextBreakStartMessage(name: "Suresh").isEmpty)
        #expect(!catalog.nextBreakDoneMessage(name: "").isEmpty)
        #expect(!catalog.nextGoalMessage(name: "Suresh").isEmpty)
    }

    @Test("messages stay short enough for a small box")
    func messagesAreShort() {
        for pool in MessageCatalog.allPools {
            for template in pool.templates {
                let filled = MessageCatalog.fill(template, name: "Suresh")
                #expect(filled.count <= 34, "too long: \(filled)")
            }
        }
    }
}

@Suite("Entrance and eye break")
struct EntranceAndBreakTests {

    @Test("greetings pop into place instead of walking in")
    func greetingPops() {
        #expect(SummonPurpose.greeting.entrance == .pop)
        #expect(SummonPurpose.celebration.entrance == .pop)
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        #expect(machine.state == .appearing(.greeting))
        #expect(machine.state.isWalking == false)
    }

    @Test("reminders still walk in")
    func remindersWalk() {
        #expect(SummonPurpose.reminder(.water).entrance == .walk)
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.water)))
        #expect(machine.state == .entering(.reminder(.water)))
        #expect(machine.state.isWalking)
    }

    @Test("after popping in she greets, then walks away")
    func popThenWalkOff() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.greeting))
        machine.handle(.arrivedAtCorner)
        #expect(machine.state == .greeting)
        machine.handle(.animationFinished)
        machine.handle(.restTimeout)
        #expect(machine.state == .leaving)
        #expect(machine.state.isWalking)
    }

    @Test("accepting an eye break starts the timed break")
    func breakStarts() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.eyeBreak)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.breakStarted)
        #expect(machine.state == .onBreak)
        #expect(machine.state.clipName == ClipName.eyeBreak)
    }

    @Test("only an eye break starts a break")
    func waterDoesNotStartBreak() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.water)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.breakStarted)
        #expect(machine.state == .reminding(.water))
    }

    @Test("she walks back off when the break ends")
    func breakEndsWithWalk() {
        let machine = CharacterStateMachine()
        machine.handle(.summon(.reminder(.eyeBreak)))
        machine.handle(.arrivedAtCorner)
        machine.handle(.breakStarted)
        machine.handle(.breakFinished)
        #expect(machine.state == .leaving)
    }

    @Test("the countdown reports time left and finishes")
    func countdown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let countdown = BreakCountdown(duration: 20, startedAt: start)
        #expect(countdown.secondsRemaining(at: start) == 20)
        #expect(countdown.isFinished(at: start) == false)
        #expect(countdown.remaining(at: start.addingTimeInterval(5)) == 15)
        #expect(countdown.isFinished(at: start.addingTimeInterval(20)))
        #expect(countdown.remaining(at: start.addingTimeInterval(99)) == 0)
    }

    @Test("countdown progress runs zero to one")
    func countdownProgress() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let countdown = BreakCountdown(duration: 20, startedAt: start)
        #expect(countdown.progress(at: start) == 0)
        #expect(countdown.progress(at: start.addingTimeInterval(10)) == 0.5)
        #expect(countdown.progress(at: start.addingTimeInterval(40)) == 1)
    }

    @Test("a zero-length break is already finished rather than dividing by zero")
    func zeroDurationBreak() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let countdown = BreakCountdown(duration: 0, startedAt: start)
        #expect(countdown.isFinished(at: start))
        #expect(countdown.progress(at: start) == 1)
    }

    @Test("every bubble style is offered and describable")
    func bubbleStyles() {
        #expect(BubbleStyle.allCases.count == 4)
        for style in BubbleStyle.allCases {
            #expect(!style.displayName.isEmpty)
            #expect(!style.detail.isEmpty)
        }
        #expect(BubbleStyle.cloud.hasTail)
        #expect(BubbleStyle.rounded.hasTail == false)
        #expect(BubbleStyle.plain.isFramed == false)
        #expect(BubbleStyle.cloud.isFramed)
    }

    @Test("break settings default to something sensible")
    func breakDefaults() {
        let defaults = AiTwinSettings.defaults
        #expect(defaults.eyeBreakDuration == 60)
        #expect(defaults.dimsScreenOnBreak)
        #expect(defaults.dimOpacity == 0.5)
        #expect(defaults.bubbleStyle == .cloud)
    }
}
