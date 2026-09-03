import AppKit
import SwiftUI
import AiTwinCore
import AiTwinPlatform
import AiTwinMac
import AiTwinUI
import SwiftUI

/// Wires the domain to the platform.
///
/// This is the only object that knows about both `ReminderEngine` and
/// `NSWindow`, and it is deliberately the *only* one: the engine decides when a
/// reminder is due, the state machine decides what the character is doing, and
/// this class does nothing but translate between them and the screen. It holds
/// no timing policy of its own.
@MainActor
final class AppCoordinator {

    // Domain
    private let engine: ReminderEngine
    private let stateMachine = CharacterStateMachine()
    private var settings: AiTwinSettings
    private let configuration: AiTwinConfiguration
    private let settingsStore: SettingsStoring

    // Platform
    private let windowManager: MacWindowManager
    private let screenProvider: MacScreenProvider
    private let idleMonitor: IdleMonitoring
    private let presence: PresenceObserving
    private let loginItem: LoginItemManaging
    private let packLoader: MacCharacterPackLoader
    private let dimmer: MacScreenDimmer
    private let sounds: SoundPlaying
    private let imageCache = FrameImageCache()
    /// Shared with the engine so reminder lines and greetings draw from one
    /// non-repeating catalogue.
    private let catalog = MessageCatalog()
    private var focus: FocusController!
    private var chatter = ChatterScheduler()
    private var moods = MoodMonitor()
    /// Decides whether coming back from a lock is worth resetting for.
    private var presenceTracker = PresenceTracker()
    private var focusTicker: Timer?
    /// Plays multi-clip routines — sitting, standing, then stretching — so a
    /// behaviour can be choreographed in code rather than baked into one clip.
    private let sequencePlayer = SequencePlayer()

    // UI
    let companionModel = CompanionViewModel()
    private(set) var pack: CharacterPack?
    private var sequencer = FrameSequencer(
        clip: AnimationClip(name: ClipName.idle, framePaths: [], frameDuration: 0.125, loops: true)
    )
    private var facing: Facing = .right

    // Timers. Three, each with one job, all invalidated on teardown.
    private var engineTimer: Timer?
    private var animationTimer: Timer?
    private var stateTimer: Timer?

    /// Called when settings change from anywhere, so the Settings window and the
    /// menu bar can follow along.
    var onSettingsChanged: ((AiTwinSettings) -> Void)?

    init(
        settingsStore: SettingsStoring,
        configuration: AiTwinConfiguration = .production,
        screenProvider: MacScreenProvider = MacScreenProvider(),
        idleMonitor: IdleMonitoring = MacIdleMonitor(),
        presence: PresenceObserving = MacPresenceObserver(),
        loginItem: LoginItemManaging = MacLoginItem(),
        packLoader: MacCharacterPackLoader = MacCharacterPackLoader(),
        dimmer: MacScreenDimmer = MacScreenDimmer(),
        sounds: SoundPlaying = MacSoundPlayer()
    ) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.configuration = configuration
        self.screenProvider = screenProvider
        self.idleMonitor = idleMonitor
        self.presence = presence
        self.loginItem = loginItem
        self.packLoader = packLoader
        self.dimmer = dimmer
        self.sounds = sounds

        self.engine = ReminderEngine(
            settings: settings,
            configuration: configuration,
            clock: SystemClock(),
            catalog: catalog,
            waterLogStore: UserDefaultsWaterLogStore(),
            activityLogStore: UserDefaultsActivityLogStore()
        )
        self.windowManager = MacWindowManager(
            size: CompanionLayout.panelSize(characterHeight: settings.characterHeight)
        )
        self.focus = FocusController(settings: settings, clock: SystemClock())
        self.chatter = ChatterScheduler(frequency: settings.chatterFrequency)
        self.moods = MoodMonitor(thresholds: settings.moodThresholds)
    }

    // MARK: Startup

    func start() {
        packLoader.createUserPacksDirectoryIfNeeded()
        loadPack()
        installContentView()
        wireCallbacks()

        companionModel.characterHeight = settings.characterHeight
        companionModel.frameHeight = frameHeight
        companionModel.anchorsToTop = !settings.corner.isBottom
        companionModel.bubbleStyle = settings.bubbleStyle
        engine.start()
        startEngineTimer()
        presence.start()
        // iCloud sync is parked -- see Docs/ROADMAP.md. It cannot be verified
        // without a paid developer account, and leaving it running meant a
        // write to a rate-limited store on every slider tick, plus a merge
        // order that could overwrite newer remote history with older local.
        // CloudSyncStore stays in the tree, unused, if it is picked back up.

        if settings.greetOnLaunch {
            greet(catalog.nextGreeting(for: Date(), name: settings.userName))
        }
    }

    func stop() {
        [engineTimer, animationTimer, stateTimer, breakTicker].forEach { $0?.invalidate() }
        engineTimer = nil
        animationTimer = nil
        stateTimer = nil
        presence.stop()
        engine.stop()
        endBreak()
        windowManager.hide()
    }

    private func installContentView() {
        let hosting = NSHostingView(rootView: CompanionOverlayView(model: companionModel))
        // The hosting view must not paint a background of its own, or the
        // transparent panel gets an opaque white rectangle back.
        hosting.layer?.backgroundColor = .clear
        // Stop SwiftUI from resizing the panel to fit its content. The window's
        // size is ours to control; letting the content drive it made the panel
        // grow and shrink as the thought cloud came and went, which moved the
        // character and turned her walk-out into a diagonal.
        hosting.sizingOptions = []
        windowManager.setContentView(hosting)
        windowManager.setSize(panelSize)
    }

    private func wireCallbacks() {
        engine.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        stateMachine.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.enter(state) }
        }
        screenProvider.onScreenConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.handleScreenChange() }
        }
        focus.onPhaseChange = { [weak self] session in
            MainActor.assumeIsolated { self?.handleFocusPhase(session) }
        }
        focus.onSessionCompleted = { [weak self] minutes in
            MainActor.assumeIsolated { self?.engine.recordFocusSession(minutes: minutes) }
        }
        presence.onAway = { [weak self] in
            MainActor.assumeIsolated { self?.handleAway() }
        }
        presence.onBack = { [weak self] in
            MainActor.assumeIsolated { self?.handleBack() }
        }
        companionModel.onPrimaryAction = { [weak self] in
            MainActor.assumeIsolated { self?.acknowledgeActiveReminder() }
        }
        companionModel.onSnoozeAction = { [weak self] in
            MainActor.assumeIsolated { self?.snoozeActiveReminder() }
        }
    }

    // MARK: Sound

    /// Plays the tone chosen for a cue, if any.
    ///
    /// Every chime in the app goes through here, so the master switch is honoured
    /// in exactly one place and there is no path that can accidentally make noise
    /// with sounds turned off.
    private func chime(_ cue: SoundCue) {
        guard let sound = settings.sounds.sound(for: cue) else { return }
        sounds.play(sound)
    }

    /// Plays a tone on demand, so Settings can audition one before you commit.
    /// Deliberately ignores the master switch: you are asking to hear it.
    func previewSound(_ sound: AlertSound) {
        sounds.play(sound)
    }

    // MARK: Engine events

    private func handle(_ event: ReminderEvent) {
        switch event {
        case .reminderDue(let kind, let message):
            chime(.reminder)
            chatter.noteReminder(at: Date())
            pendingMessage = message
            stateMachine.handle(.summon(.reminder(kind)))

        case .reminderAcknowledged(let kind):
            moods.noteAccepted(at: Date())
            if kind == .water {
                // Logging the glass may already have triggered a goal or streak
                // celebration, which has words and outranks this. Only claim the
                // wordless jump if nothing else took the moment -- otherwise the
                // flag latched on and muted the *next* celebration instead.
                if stateMachine.state == .celebrating {
                    break
                }
                celebrationRoutine = .waterLoggedRoutine
                pendingMessage = nil
                silentCelebration = true
                if stateMachine.handle(.summon(.celebration)) != .celebrating {
                    silentCelebration = false
                    stateMachine.handle(.reminderResolved)
                }
            } else if stateMachine.state != .onBreak {
                // Never while a break is running: resolving would walk her off
                // and leave the screen dimmed with no countdown.
                stateMachine.handle(.reminderResolved)
            }

        case .reminderSnoozed:
            moods.noteSkipped()
            stateMachine.handle(.reminderResolved)

        case .reminderTimedOut:
            moods.noteSkipped()
            // Nobody was there. Leave quietly.
            stateMachine.handle(.reminderResolved)

        case .reminderWithdrawn:
            moods.noteSkipped()
            // `.reset`, not `.reminderResolved`: resolving walks her off screen
            // over a second or more, and the screen is already locked. `.reset`
            // lands in `.hidden` immediately, which stops the animation, ends
            // any running eye break and undims the display.
            stateMachine.handle(.reset)

        case .waterLogged(let glasses, let goal, let goalJustReached):
            if goalJustReached {
                // A milestone outranks the everyday goal line.
                if engine.streakMilestoneReachedToday() != nil {
                    // Wordless: the jump is the message.
                    silentCelebration = true
                    celebrate("", routine: .milestoneRoutine)
                } else {
                    celebrate(catalog.nextGoalMessage(name: settings.userName))
                }
            }
            onWaterCountChanged?(glasses, goal)
        }
    }

    private var pendingMessage: String?
    var onWaterCountChanged: ((Int, Int) -> Void)?

    /// The running eye-break countdown, if one is active.
    private var breakCountdown: BreakCountdown?
    private var breakTicker: Timer?

    // MARK: State machine

    private func enter(_ state: CharacterState) {
        stateTimer?.invalidate()
        stateTimer = nil

        // Only a focus session shows a clock in the cloud, and .focusing sets
        // it again immediately. Clearing here means no other state can inherit
        // a stale countdown.
        companionModel.countdown = nil

        // Track whether the pose currently on screen is the peek, so the exit
        // can match the entrance. Set on entry to *any* state that shows the
        // peek clip -- the developer previews show it too, and previously only
        // real chatter set the flag, so previewing a peek ended in a walk-off
        // and the fix looked broken exactly where it was being tested.
        //
        // `.leaving` is excluded from clearing because it is the state that
        // reads the flag. Without that, the flag also used to latch on and turn
        // every later walk-out into a short slide.
        if Self.showsPeekPose(state) {
            wasPeeking = true
        } else if state != .leaving {
            wasPeeking = false
        }

        switch state {
        case .hidden:
            stopAnimation()
            stopSequence()
            endBreak()
            windowManager.setInteractive(false)
            companionModel.bubble = nil
            companionModel.entranceProgress = 1
            windowManager.hide()

        case .entering(let purpose):
            companionModel.entranceProgress = 1
            facing = settings.corner.entryFacing
            applyClip(named: ClipName.walk)
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            windowManager.setPosition(entryOrigin())
            windowManager.show()
            startAnimation()
            let destination = restingOrigin()
            let duration = CharacterPlacement.walkDuration(
                from: entryOrigin(), to: destination, speed: configuration.walkingSpeed
            )
            windowManager.move(to: destination, duration: duration) { [weak self] in
                MainActor.assumeIsolated {
                    _ = purpose   // the purpose is carried in the state itself
                    _ = self?.stateMachine.handle(.arrivedAtCorner)
                }
            }

        case .appearing(let purpose):
            // Materialise in place rather than walking in. Walking in every
            // single time reads as repetitive, and a spontaneous hello is not
            // something you cross the screen to deliver.
            facing = settings.corner.entryFacing
            applyClip(named: Self.entranceClip(for: purpose, celebration: celebrationRoutine))
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            windowManager.setPosition(restingOrigin())
            companionModel.entranceProgress = 0
            windowManager.show()
            startAnimation()
            withAnimation(.spring(response: configuration.popDuration * 0.85,
                                  dampingFraction: 0.66)) {
                companionModel.entranceProgress = 1
            }
            scheduleStateEvent(.arrivedAtCorner, after: configuration.popDuration)

        case .previewingSequence(let name):
            guard let routine = ClipSequence.named(name) else {
                stateMachine.handle(.restTimeout)
                return
            }
            play(routine)
            companionModel.bubble = CompanionViewModel.Bubble(
                message: "\(name)  ·  \(routine.steps.count) beats"
            )
            windowManager.setInteractive(false)
            if Self.showsPeekPose(state) { slideInFromEdge() }
            // An indefinite routine has no natural end, so cap the preview.
            let span = routine.duration > 0 ? routine.duration + 1 : configuration.previewDuration
            scheduleStateEvent(.restTimeout, after: span)

        case .previewing(let clip):
            stopSequence()
            // Settings → Developer plays a named clip so new art can be checked
            // without waiting for the situation that triggers it.
            applyClip(named: clip)
            let available = pack?.clips[clip] != nil
            companionModel.bubble = CompanionViewModel.Bubble(
                message: available ? clip : "\(clip) — no art, using idle"
            )
            windowManager.setInteractive(false)
            if Self.showsPeekPose(state) { slideInFromEdge() }
            scheduleStateEvent(.restTimeout, after: configuration.previewDuration)

        case .feeling(let mood):
            applyClip(named: mood.clipName)
            switch mood {
            case .concerned:
                // She walked over to say this, so it gets an answer -- and then
                // she marches off rather than drifting away.
                companionModel.bubble = CompanionViewModel.Bubble(
                    message: pendingMessage ?? "You okay?",
                    primaryTitle: "I'm okay",
                    showsSnooze: false
                )
                windowManager.setInteractive(true)
                // She waits for an answer rather than leaving on a timer, and
                // goes off happy once she has one -- she came to check on you,
                // not to tell you off.
                scheduleStateEvent(.restTimeout, after: configuration.reminderTimeout * 2)
            case .sleepy:
                companionModel.bubble = CompanionViewModel.Bubble(message: pendingMessage ?? "…")
                windowManager.setInteractive(false)
                // Two yawns and then she goes, at night as much as in the day.
                // She used to settle into the sleep pose and stay parked on the
                // desktop until something woke her, which stopped reading as a
                // nudge to stop working and started reading as clutter.
                play(.sleepRoutine)
                scheduleStateEvent(.restTimeout, after: ClipSequence.sleepRoutine.duration)
            }
            pendingMessage = nil

        case .sleeping:
            // The sleep routine parks on its final beat; release it so she is
            // properly asleep rather than mid-yawn.
            sequencePlayer.release(at: Date())
            applyClip(named: ClipName.sleep)
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            scheduleStateEvent(.restTimeout, after: configuration.sleepDuration)

        case .chattering:
            // Leans in from the very edge of the display rather than walking on
            // or popping up mid-screen. The peeking artwork is drawn against a
            // vertical border, so it only makes sense flush to the screen edge.
            applyClip(named: ClipName.peek)
            companionModel.bubble = CompanionViewModel.Bubble(message: pendingMessage ?? "👋")
            pendingMessage = nil
            slideInFromEdge()
            // Bounded: she peeks, says her piece and withdraws.
            scheduleStateEvent(.restTimeout, after: configuration.chatterDuration)

        case .focusing:
            applyClip(named: ClipName.focus)
            windowManager.setInteractive(true)
            updateFocusBubble()

        case .onBreak:
            applyClip(named: ClipName.eyeBreak)
            windowManager.setInteractive(true)
            startBreak()

        case .greeting:
            play(.greetingRoutine)
            companionModel.bubble = CompanionViewModel.Bubble(message: pendingMessage ?? "Hi 👋")
            pendingMessage = nil
            scheduleStateEvent(.animationFinished, after: configuration.greetingDuration)

        case .celebrating:
            play(celebrationRoutine)
            let routine = celebrationRoutine
            celebrationRoutine = .waterLoggedRoutine
            if silentCelebration {
                silentCelebration = false
                companionModel.bubble = nil
                pendingMessage = nil
                windowManager.setInteractive(false)
                scheduleStateEvent(.restTimeout, after: routine.duration)
                return
            }
            companionModel.bubble = CompanionViewModel.Bubble(message: pendingMessage ?? "Nice one 🎉")
            pendingMessage = nil
            windowManager.setInteractive(false)
            scheduleStateEvent(.restTimeout, after: configuration.greetingDuration)

        case .idle:
            applyClip(named: ClipName.idle)
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            scheduleStateEvent(.restTimeout, after: configuration.idleRestDuration)

        case .reminding(let kind):
            // A stretch reminder is a routine: sit, stand, reach. The point of
            // the reminder is the getting up, so she demonstrates it.
            if kind == .stretch {
                play(.stretchRoutine)
            } else {
                stopSequence()
                applyClip(named: kind.clipName)
            }
            companionModel.bubble = CompanionViewModel.Bubble(
                message: pendingMessage ?? kind.displayName,
                primaryTitle: kind.acknowledgeTitle,
                showsSnooze: true
            )
            pendingMessage = nil
            // The only moment in the app's life when clicks do not pass through.
            windowManager.setInteractive(true)

        case .leaving where wasPeeking:
            // Withdraw the way she arrived: a short slide back off the edge.
            wasPeeking = false
            stopSequence()
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            windowManager.move(to: peekEntryOrigin(), duration: 0.4) { [weak self] in
                MainActor.assumeIsolated { _ = self?.stateMachine.handle(.exitedScreen) }
            }

        case .leaving:
            endBreak()
            // Stop any routine still running, or its next beat overwrites the
            // walk clip mid-exit and she slides off in an idle pose.
            stopSequence()
            companionModel.entranceProgress = 1
            applyClip(named: ClipName.walk)
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            // Turn around: the walk-out is the walk-in clip, mirrored.
            facing = settings.corner.entryFacing == .right ? .left : .right
            companionModel.facing = facing
            let exit = entryOrigin()
            // She leaves a concern briskly -- a point made, then gone.
            let speed = configuration.walkingSpeed * (hurriedExit ? configuration.hurriedExitMultiplier : 1)
            hurriedExit = false
            let duration = CharacterPlacement.walkDuration(
                from: windowManager.currentOrigin, to: exit, speed: speed
            )
            windowManager.move(to: exit, duration: duration) { [weak self] in
                MainActor.assumeIsolated { _ = self?.stateMachine.handle(.exitedScreen) }
            }
        }
    }

    /// The clip shown while materialising, chosen from why she was summoned.
    private static func entranceClip(for purpose: SummonPurpose, celebration: ClipSequence) -> String {
        switch purpose {
        case .greeting:          return ClipName.wave
        case .celebration:       return celebration.clips.first ?? ClipName.happy
        case .chatter:           return ClipName.peek
        case .focus:             return ClipName.focus
        case .mood(let mood):    return mood.clipName
        case .preview(let clip): return clip
        case .previewSequence(let name):
            return ClipSequence.named(name)?.clips.first ?? ClipName.idle
        case .reminder(let k):   return k.clipName
        }
    }

    private func scheduleStateEvent(_ event: CharacterEvent, after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stateMachine.handle(event) }
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
    }

    // MARK: Actions

    private func acknowledgeActiveReminder() {
        // "Skip" while the break is running just ends it early.
        if stateMachine.state == .onBreak {
            stateMachine.handle(.breakFinished)
            return
        }
        // "End" during a focus session stops the whole session.
        if stateMachine.state == .focusing {
            stopFocusSession()
            return
        }
        // "I'm okay" — she is reassured, gives a quick happy beat, and goes.
        if stateMachine.state == .feeling(.concerned) {
            silentCelebration = true
            celebrationRoutine = .waterLoggedRoutine
            if stateMachine.handle(.summon(.celebration)) != .celebrating {
                silentCelebration = false
                stateMachine.handle(.restTimeout)
            }
            return
        }
        guard let kind = engine.activeReminder else { return }
        let startsBreak = kind == .eyeBreak && settings.dimsScreenOnBreak && settings.eyeBreakDuration > 0
        // Order matters, and getting it wrong silently killed the whole eye
        // break: `acknowledge` synchronously reports .reminderAcknowledged,
        // which resolves the reminder and sends her walking off. By the time
        // .breakStarted arrived the state was .leaving, the transition was
        // rejected, and .onBreak -- the state that dims the screen and starts
        // the countdown -- was never entered. So enter the break *first*,
        // while she is still .reminding(.eyeBreak).
        if startsBreak {
            stateMachine.handle(.breakStarted)
        }
        engine.acknowledge(kind)
    }

    private func snoozeActiveReminder() {
        guard let kind = engine.activeReminder else { return }
        engine.snooze(kind)
    }

    /// Says hello on demand.
    ///
    /// For when someone launches AiTwin while it is already running. macOS does
    /// not start a second copy, so `applicationDidFinishLaunching` never runs
    /// again and the launch-time greeting never fires -- the app looked like it
    /// had done nothing at all. Skipped if she is already on screen, so this
    /// cannot interrupt a reminder.
    func greetOnDemand() {
        guard stateMachine.state == .hidden else { return }
        greet(catalog.nextGreeting(for: Date(), name: settings.userName))
    }

    func greet(_ message: String) {
        pendingMessage = message
        stateMachine.handle(.summon(.greeting))
    }

    // MARK: Eye break

    private func startBreak() {
        let countdown = BreakCountdown(duration: settings.eyeBreakDuration, startedAt: Date())
        breakCountdown = countdown
        dimmer.dim(to: settings.dimOpacity, over: 0.8)

        // Her cloud says its piece once and then holds still. The countdown
        // itself goes across the middle of the dimmed screen: it is the one
        // thing you are meant to be able to read without looking at the corner
        // you were just asked to look away from.
        companionModel.bubble = CompanionViewModel.Bubble(
            message: catalog.nextBreakStartMessage(name: settings.userName),
            primaryTitle: "Skip",
            showsSnooze: false
        )
        showBreakCountdown(at: Date())

        breakTicker?.invalidate()
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let countdown = self.breakCountdown else { return }
                let now = Date()
                if countdown.isFinished(at: now) {
                    self.finishBreak()
                } else {
                    self.showBreakCountdown(at: now)
                }
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        breakTicker = ticker
    }

    private func showBreakCountdown(at now: Date) {
        guard let countdown = breakCountdown else { return }
        // Ticks four times a second so the countdown never visibly stutters;
        // the text itself changes once a second and setting the same string
        // again is a no-op on the label.
        dimmer.setCountdown(countdown.clockText(at: now),
                            caption: BreakCountdown.overlayCaption)
    }

    private func finishBreak() {
        endBreak()
        // The whole point of the break is that you are not looking at the
        // screen, so this is the cue that most needs a sound.
        chime(.breakOver)
        companionModel.bubble = CompanionViewModel.Bubble(
            message: catalog.nextBreakDoneMessage(name: settings.userName)
        )
        // She vanishes rather than walking off: the break ended because you
        // looked away, so a walk back across the screen would only pull your
        // eyes to it again. Fading out mirrors the pop-in she arrived with.
        vanish(after: configuration.greetingDuration)
    }

    /// Leans in from just off the screen edge: the peek's entrance.
    ///
    /// Shared by real chatter and by the Developer previews, so a preview shows
    /// the placement and the withdrawal the feature actually has. The exit in
    /// `.leaving where wasPeeking` is the exact reverse of this.
    private func slideInFromEdge() {
        facing = settings.corner.isLeft ? .right : .left
        companionModel.facing = facing
        windowManager.setInteractive(false)
        windowManager.setPosition(peekEntryOrigin())
        windowManager.show()
        startAnimation()
        windowManager.move(to: peekOrigin(), duration: 0.45) { }
    }

    /// Fades the character out in place, then hides the window.
    private func vanish(after delay: TimeInterval) {
        stateTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.companionModel.bubble = nil
                withAnimation(.easeIn(duration: self.configuration.popDuration * 0.7)) {
                    self.companionModel.entranceProgress = 0
                }
                // Hide once the fade has finished playing.
                let hide = Timer(timeInterval: self.configuration.popDuration * 0.7, repeats: false) { _ in
                    MainActor.assumeIsolated { _ = self.stateMachine.handle(.reset) }
                }
                RunLoop.main.add(hide, forMode: .common)
                self.stateTimer = hide
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
    }

    /// Stops the countdown and restores brightness. Safe to call repeatedly.
    private func endBreak() {
        breakTicker?.invalidate()
        breakTicker = nil
        breakCountdown = nil
        dimmer.setCountdown(nil, caption: nil)
        if dimmer.isDimmed { dimmer.undim(over: 0.5) }
    }

    /// Pops out to celebrate. Skipped while a reminder is being handled, so the
    /// celebration cannot interrupt the thing that earned it.
    private func celebrate(_ message: String, routine: ClipSequence = .waterLoggedRoutine) {
        guard engine.activeReminder == nil, !stateMachine.state.isWalking else {
            companionModel.bubble = CompanionViewModel.Bubble(message: message)
            return
        }
        celebrationRoutine = routine
        pendingMessage = message
        stateMachine.handle(.summon(.celebration))
    }

    /// Which clip the next celebration uses -- `happy` normally, `cheer` for a
    /// streak milestone.
    private var celebrationRoutine = ClipSequence.waterLoggedRoutine
    /// A celebration with no words -- used after you log a glass of water.
    private var silentCelebration = false
    /// True while the pose on screen is the peek, so the exit matches the
    /// entrance: she withdraws around the edge instead of walking off.
    private var wasPeeking = false

    /// Whether a state draws the peeking pose.
    ///
    /// Chatter is the real one; the two preview states matter because the
    /// Developer tab is how the behaviour gets checked, and a preview that
    /// walks off is not previewing the behaviour.
    private static func showsPeekPose(_ state: CharacterState) -> Bool {
        switch state {
        case .chattering:
            return true
        case .previewing(let clip):
            return clip == ClipName.peek
        case .previewingSequence(let name):
            return name == ClipSequence.peekRoutine.name
        default:
            return false
        }
    }
    /// Set when the next exit should be brisk rather than a stroll.
    private var hurriedExit = false

    func triggerReminder(_ kind: ReminderKind) {
        engine.triggerNow(kind)
    }

    // MARK: Focus sessions

    var focusSession: FocusSession? { focus.session }

    func startFocusSession() {
        focus.start()
        startFocusTicker()
    }

    func stopFocusSession() {
        focus.stop()
        focusTicker?.invalidate()
        focusTicker = nil
        engine.isFocusing = false
        if stateMachine.state == .focusing { stateMachine.handle(.focusFinished) }
    }

    func skipFocusPhase() {
        focus.skip()
    }

    private func startFocusTicker() {
        focusTicker?.invalidate()
        // Half-second so the countdown above her head does not visibly stutter.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.focus.tick()
                self.updateFocusBubble()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        focusTicker = timer
    }

    private func handleFocusPhase(_ session: FocusSession?) {
        guard let session else {
            engine.isFocusing = false
            return
        }
        // Only *working* suppresses reminders; the break is when held reminders
        // are meant to arrive.
        engine.isFocusing = session.phase == .working

        if session.endsAPreviousPhase { chime(.focusPhase) }

        if session.phase == .working {
            stateMachine.handle(.summon(.focus))
        } else {
            // Break: she gets up, cheers the session, and walks away. Anything
            // held during the session comes through as soon as she has gone.
            // Look up from the book, stand, cheer.
            celebrationRoutine = .focusFinishedRoutine
            pendingMessage = catalog.nextFocusDoneMessage(name: settings.userName)
            stateMachine.handle(.summon(.celebration))
        }
    }

    private func updateFocusBubble() {
        guard stateMachine.state == .focusing, let session = focus.session else { return }
        // The cloud itself is set once per phase and then left alone; only the
        // clock changes on a tick. Rebuilding the bubble every second replayed
        // its entrance animation each time, which is exactly as distracting as
        // it sounds.
        let bubble = CompanionViewModel.Bubble(
            message: session.phase.displayName,
            primaryTitle: "End",
            showsSnooze: false
        )
        if companionModel.bubble != bubble { companionModel.bubble = bubble }
        // The ticker runs twice a second but the clock only changes once, so
        // half the ticks have nothing to publish.
        let clock = session.clockText(at: Date())
        if companionModel.countdown != clock { companionModel.countdown = clock }
    }

    #if AITWIN_DEV
    /// Replaces the history with sample data. Debug builds only.
    func loadSampleHistory() {
        engine.replaceActivityLog(DeveloperFixtures.sampleActivityLog())
    }

    /// Empties the history, for checking the empty states.
    func clearHistory() {
        engine.replaceActivityLog(DeveloperFixtures.emptyActivityLog())
    }
    #endif

    // MARK: Stats

    var currentStreak: Int { engine.currentStreak() }
    var bestStreak: Int { engine.bestStreak() }
    var activityLog: ActivityLog { engine.activityLog }

    /// Drops hour-by-hour detail recorded before `cutoff`. Every daily total is
    /// kept -- see `DataRetention` for why the two halves differ.
    func clearOldDetail(before cutoff: Date) {
        engine.clearEventDetail(before: cutoff)
    }

    /// The hour-by-hour detail as CSV. Empty of rows when nothing is recorded.
    func exportEventsCSV() -> String {
        engine.activityLog.eventsCSV()
    }

    var hasDetailToExport: Bool { !engine.activityLog.events.isEmpty }

    /// The history as CSV, ready to save.
    func exportCSV() -> String {
        engine.activityLog.csv(intake: settings.water)
    }

    /// Plays one clip on demand. Backs the mood test buttons in Settings.
    func previewClip(_ name: String) {
        guard engine.activeReminder == nil else { return }
        stateMachine.handle(.summon(.preview(name)))
    }

    /// Plays a whole routine on demand, so a behaviour can be checked end to end.
    func previewSequence(_ name: String) {
        guard engine.activeReminder == nil else { return }
        stateMachine.handle(.summon(.previewSequence(name)))
    }

    /// Clips the current pack actually provides, for the test buttons.
    var availableClipNames: [String] {
        ClipName.loadable.filter { pack?.clips[$0] != nil }
    }

    func logWaterManually() {
        engine.logWaterManually()
    }

    func setPaused(_ paused: Bool) {
        var updated = settings
        updated.remindersPaused = paused
        apply(updated)
    }

    // MARK: Settings

    var currentSettings: AiTwinSettings { settings }
    var waterLog: WaterLog { engine.waterLog }
    var holdReason: EngineHoldReason? { engine.holdReason }

    func timeRemaining(for kind: ReminderKind) -> TimeInterval? {
        engine.timeRemaining(for: kind)
    }

    func apply(_ newSettings: AiTwinSettings) {
        let previous = settings
        settings = newSettings
        settingsStore.save(newSettings)
        engine.apply(newSettings)
        focus.apply(newSettings)
        chatter.frequency = newSettings.chatterFrequency
        moods.thresholds = newSettings.moodThresholds

        if previous.startAtLogin != newSettings.startAtLogin {
            let succeeded = loginItem.setEnabled(newSettings.startAtLogin)
            if !succeeded {
                onLoginItemFailure?("macOS did not accept the change. Approve AiTwin under System Settings › General › Login Items.")
            }
        }

        if previous.characterPackName != newSettings.characterPackName {
            loadPack()
        }

        companionModel.bubbleStyle = newSettings.bubbleStyle
        companionModel.anchorsToTop = !newSettings.corner.isBottom

        if previous.characterHeight != newSettings.characterHeight {
            companionModel.characterHeight = newSettings.characterHeight
            companionModel.frameHeight = frameHeight
            windowManager.setSize(panelSize)
        }

        // A frame-rate or corner change should be visible immediately rather
        // than at the next reminder.
        if previous.corner != newSettings.corner, stateMachine.state.isVisible {
            windowManager.setPosition(restingOrigin())
        }

        onSettingsChanged?(newSettings)
    }

    var onLoginItemFailure: ((String) -> Void)?

    func reloadPacks() {
        loadPack()
    }

    /// Installs a pack from a dropped zip or folder, normalising it on the way in.
    /// - Returns: a sentence describing what happened, for the drop zone.
    func installPack(from url: URL) -> String {
        let installer = PackInstaller(destinationRoot: packLoader.userPacksDirectory)
        packLoader.createUserPacksDirectoryIfNeeded()
        do {
            let result = try installer.install(from: url)
            // Switch to it straight away: someone who just installed a character
            // wants to see her, not hunt for a picker.
            var updated = settings
            updated.characterPackName = result.name
            apply(updated)

            var summary = "Installed “\(result.name)” — \(result.framesInstalled) frames, "
                + "\(result.clipsInstalled.count) animations, \(result.canvas)."
            if !result.clipsMissing.isEmpty {
                summary += " No art for: \(result.clipsMissing.joined(separator: ", ")) — those fall back to idle."
            }
            return summary
        } catch {
            return "Could not install that: \(error.localizedDescription)"
        }
    }

    func availablePackNames() -> [String] {
        let names = packLoader.availablePackNames()
        return names.isEmpty ? [CharacterPack.defaultPackName] : names
    }

    var userPacksDirectory: URL { packLoader.userPacksDirectory }

    var missingClipNames: [String] { pack?.missingClipNames ?? ClipName.all }

    // MARK: Character pack

    private func loadPack() {
        let loaded = packLoader.loadPack(
            named: settings.characterPackName,
            frameDuration: configuration.animationFrameDuration
        )
        // Fall back to the bundled pack if the chosen one is unusable, so a
        // deleted folder cannot leave the app with no character at all.
        pack = loaded ?? packLoader.loadPack(
            named: CharacterPack.defaultPackName,
            frameDuration: configuration.animationFrameDuration
        )
        if let pack { imageCache.preload(pack) }
        // The pack decides how much headroom a frame carries, so its size feeds
        // straight back into the panel.
        companionModel.frameHeight = frameHeight
        windowManager.setSize(panelSize)
        // Sample her colours so the thought cloud and buttons match the art.
        companionModel.palette = CharacterPaletteExtractor.palette(for: pack, cache: imageCache)
        applyClip(named: stateMachine.state.clipName)
    }

    private func applyClip(named name: String) {
        guard let pack,
              let clip = pack.resolveClip(named: name)
        else {
            // No art at all: the view falls back to its vector placeholder.
            companionModel.image = nil
            companionModel.facing = facing
            companionModel.headHeight = frameHeight
            return
        }
        sequencer.setClip(clip)
        companionModel.facing = facing
        companionModel.headHeight = clip.headHeight(inFrameOf: frameHeight)
        updateImage()
    }

    private func updateImage() {
        guard let path = sequencer.currentFramePath else {
            companionModel.image = nil
            return
        }
        companionModel.image = imageCache.image(at: path)
    }

    // MARK: Timers

    private func startEngineTimer() {
        engineTimer?.invalidate()
        let timer = Timer(timeInterval: configuration.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let idle = self.idleMonitor.idleSeconds
                self.engine.tick(idleSeconds: idle)
                // Nothing below may run while the screen is locked. Pausing the
                // engine is not enough on its own: moods and chatter build
                // their own conditions and their only away-guard is a
                // three-minute idle threshold, while the idle monitor counts
                // password typing at the login window as activity. Without this
                // she could peek onto a lock screen.
                guard !self.engine.isAway else { return }
                self.updateMoodMonitor(idleSeconds: idle)
                // A mood is the more meaningful interruption, so it gets first
                // refusal; chatter only fills the silence it leaves.
                if !self.maybeShowMood(idleSeconds: idle) {
                    self.maybeChatter(idleSeconds: idle)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        engineTimer = timer
    }

    /// The animation timer runs only while the character is on screen, so an
    /// idle AiTwin costs one wake-up per second and nothing else.
    private func startAnimation() {
        guard animationTimer == nil else { return }
        let step = configuration.animationFrameDuration
        let timer = Timer(timeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sequencer.advance(by: step)
                self.advanceSequence()
                self.updateImage()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// Moves a running routine to its next beat when the current one is over.
    private func advanceSequence() {
        guard sequencePlayer.sequence != nil, !sequencePlayer.isFinished else { return }
        if sequencePlayer.tick(at: Date(), clipFinished: sequencer.isFinished),
           let clip = sequencePlayer.currentClip {
            applyClip(named: clip)
        }
    }

    /// Starts a routine and shows its first beat.
    private func play(_ sequence: ClipSequence) {
        sequencePlayer.start(sequence, at: Date())
        if let clip = sequencePlayer.currentClip { applyClip(named: clip) }
    }

    private func stopSequence() {
        sequencePlayer.stop()
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Keeps the animation running for as long as the character is visible.
    private func ensureAnimationMatchesVisibility() {
        stateMachine.state.isVisible ? startAnimation() : stopAnimation()
    }

    /// Whether the clock is inside the user's configured night window.
    private func isNight(at now: Date = Date()) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let start = settings.moodThresholds.nightStartMinutes
        return minuteOfDay >= start || minuteOfDay < 5 * 60
    }

    // MARK: Moods

    /// Keeps the monitor's picture of the day current.
    private func updateMoodMonitor(idleSeconds: TimeInterval) {
        if idleSeconds >= MoodMonitor.maximumIdleSeconds {
            moods.noteAway()
        } else {
            moods.noteActive(at: Date())
        }
    }

    /// Shows concern or sleepiness when the day warrants it.
    /// - Returns: whether a mood was shown, so chatter can stand down.
    @discardableResult
    private func maybeShowMood(idleSeconds: TimeInterval) -> Bool {
        let now = Date()
        let conditions = MoodMonitor.Conditions(
            isPaused: settings.remindersPaused,
            inQuietHours: settings.quietHours.contains(now),
            isFocusing: focus.isActive,
            characterIsBusy: stateMachine.state != .hidden || engine.activeReminder != nil,
            idleSeconds: idleSeconds
        )
        guard settings.moodsEnabled,
              let mood = moods.mood(at: now, conditions: conditions) else { return false }
        moods.noteMoodShown(mood, at: now)
        pendingMessage = mood == .concerned
            ? catalog.nextConcernedMessage(name: settings.userName)
            : catalog.nextSleepyMessage(name: settings.userName)
        stateMachine.handle(.summon(.mood(mood)))
        return true
    }

    // MARK: Idle chatter

    /// Offers an unprompted line, subject to every limit in `ChatterScheduler`.
    private func maybeChatter(idleSeconds: TimeInterval) {
        let now = Date()
        let conditions = ChatterScheduler.Conditions(
            isPaused: settings.remindersPaused,
            inQuietHours: settings.quietHours.contains(now),
            isFocusing: focus.isActive,
            characterIsBusy: stateMachine.state != .hidden || engine.activeReminder != nil,
            idleSeconds: idleSeconds
        )
        guard chatter.shouldChatter(at: now, conditions: conditions) else { return }
        chatter.noteChatter(at: now)
        pendingMessage = catalog.nextChatterMessage(name: settings.userName)
        stateMachine.handle(.summon(.chatter))
    }

    // MARK: Screen geometry

    /// Rendered frame height for the current pack, so the character measures
    /// `settings.characterHeight` regardless of how much headroom the art needs.
    private var frameHeight: Double {
        pack?.frameHeight(forCharacterHeight: settings.characterHeight) ?? settings.characterHeight
    }

    private var panelSize: GSize {
        CompanionLayout.panelSize(
            characterHeight: settings.characterHeight,
            frameHeight: frameHeight
        )
    }

    private var visibleFrame: GRect {
        // If every display vanished mid-flight, fall back to something sane
        // rather than crashing on an empty array.
        screenProvider.activeScreen?.visibleFrame
            ?? GRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func restingOrigin() -> GPoint {
        CharacterPlacement.restingOrigin(
            corner: settings.corner,
            size: panelSize,
            visibleFrame: visibleFrame,
            margin: configuration.edgeMargin
        )
    }

    private var screenFrame: GRect {
        screenProvider.activeScreen?.frame ?? visibleFrame
    }

    private func peekOrigin() -> GPoint {
        CharacterPlacement.peekOrigin(
            corner: settings.corner, size: panelSize,
            visibleFrame: visibleFrame, screenFrame: screenFrame,
            artInset: peekArtInset
        )
    }

    /// Just off the edge, far enough that none of her shows.
    private func peekEntryOrigin() -> GPoint {
        CharacterPlacement.peekEntryOrigin(
            corner: settings.corner, size: panelSize,
            visibleFrame: visibleFrame,
            artInset: peekArtInset, artWidth: peekArtWidth,
            screenFrame: screenFrame
        )
    }

    /// How far her first visible pixel sits inside the panel's own edge.
    ///
    /// Zero for a pack whose peek art could not be measured, which restores the
    /// old panel-aligned behaviour rather than guessing.
    private var peekArtInset: Double {
        guard let pack, let bounds = pack.peekBounds else { return 0 }
        return CompanionLayout.edgeArtInset(
            panelWidth: panelSize.width,
            frameHeight: frameHeight,
            canvasAspectRatio: pack.canvasAspectRatio,
            leadingFraction: bounds.leadingFraction
        )
    }

    private var peekArtWidth: Double {
        guard let pack, let bounds = pack.peekBounds else {
            return configuration.peekSlideDistance
        }
        return CompanionLayout.artWidth(
            frameHeight: frameHeight,
            canvasAspectRatio: pack.canvasAspectRatio,
            widthFraction: bounds.widthFraction
        )
    }

    private func entryOrigin() -> GPoint {
        CharacterPlacement.entryOrigin(
            corner: settings.corner,
            size: panelSize,
            visibleFrame: visibleFrame,
            margin: configuration.edgeMargin
        )
    }

    /// A display was connected, disconnected or resized.
    private func handleScreenChange() {
        guard stateMachine.state.isVisible else { return }
        // Re-clamp rather than recompute: if the character was mid-walk we do
        // not want to teleport it to the corner, only to bring it back on screen.
        let clamped = CharacterPlacement.clamp(
            windowManager.currentOrigin, size: panelSize, to: visibleFrame
        )
        windowManager.setPosition(clamped)
        ensureAnimationMatchesVisibility()
    }

    // MARK: Away and back

    /// The screen locked, the Mac slept, or the screensaver came on.
    private func handleAway() {
        guard presenceTracker.noteAway(at: Date()) else { return }

        // A focus session does not survive a lock. Ending it rather than
        // pausing it is deliberate: a Pomodoro you walked away from halfway is
        // not a Pomodoro, and `focus.stop()` deliberately does not report a
        // completed session, so nothing is logged for work that did not happen.
        //
        // Must run before the reset below, because it checks for `.focusing`.
        if focus.isActive { stopFocusSession() }

        // Stops every countdown and withdraws anything already on screen.
        engine.beginAway()

        // Drop the unbroken-work stretch, so a locked screen can never count
        // toward "you have been at this for three hours".
        moods.noteAway()

        // Straight to hidden rather than a walk-out: the display is already off
        // or locked, so an exit animation is a second of work nobody can see.
        // `.hidden` is also what stops the animation timer, ends any running
        // eye break and undims the screen.
        stateMachine.handle(.reset)
    }

    /// The user unlocked, or the Mac woke.
    private func handleBack() {
        let now = Date()
        switch presenceTracker.noteBack(at: now) {
        case .spurious:
            return
        case .brief:
            // A minute fetching a coffee. Pick up exactly where she left off:
            // no reset, no hello.
            engine.endAway(resetCycles: false)
        case .significant:
            // Time away from the Mac is not screen time, so every cycle starts
            // again from the moment they sat back down.
            engine.endAway(resetCycles: true)
            greetOnReturn(at: now)
        }
    }

    private func greetOnReturn(at now: Date) {
        guard settings.greetOnWake, !settings.remindersPaused else { return }
        guard !settings.quietHours.contains(now) else { return }
        guard stateMachine.state == .hidden else { return }
        greet(catalog.nextWakeGreeting(for: now, name: settings.userName))
    }
}
