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
    private let wakeObserver: WakeObserving
    private let loginItem: LoginItemManaging
    private let packLoader: MacCharacterPackLoader
    private let dimmer: MacScreenDimmer
    private let imageCache = FrameImageCache()
    /// Shared with the engine so reminder lines and greetings draw from one
    /// non-repeating catalogue.
    private let catalog = MessageCatalog()

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
        wakeObserver: WakeObserving = MacWakeObserver(),
        loginItem: LoginItemManaging = MacLoginItem(),
        packLoader: MacCharacterPackLoader = MacCharacterPackLoader(),
        dimmer: MacScreenDimmer = MacScreenDimmer()
    ) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.configuration = configuration
        self.screenProvider = screenProvider
        self.idleMonitor = idleMonitor
        self.wakeObserver = wakeObserver
        self.loginItem = loginItem
        self.packLoader = packLoader
        self.dimmer = dimmer

        self.engine = ReminderEngine(
            settings: settings,
            configuration: configuration,
            clock: SystemClock(),
            catalog: catalog,
            waterLogStore: UserDefaultsWaterLogStore()
        )
        self.windowManager = MacWindowManager(
            size: CompanionLayout.panelSize(characterHeight: settings.characterHeight)
        )
    }

    // MARK: Startup

    func start() {
        packLoader.createUserPacksDirectoryIfNeeded()
        loadPack()
        installContentView()
        wireCallbacks()

        companionModel.characterHeight = settings.characterHeight
        companionModel.bubbleStyle = settings.bubbleStyle
        engine.start()
        startEngineTimer()
        wakeObserver.start()

        if settings.greetOnLaunch {
            greet(catalog.nextGreeting(for: Date(), name: settings.userName))
        }
    }

    func stop() {
        [engineTimer, animationTimer, stateTimer, breakTicker].forEach { $0?.invalidate() }
        engineTimer = nil
        animationTimer = nil
        stateTimer = nil
        wakeObserver.stop()
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
        windowManager.setSize(CompanionLayout.panelSize(characterHeight: settings.characterHeight))
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
        wakeObserver.onWake = { [weak self] in
            MainActor.assumeIsolated { self?.handleWake() }
        }
        companionModel.onPrimaryAction = { [weak self] in
            MainActor.assumeIsolated { self?.acknowledgeActiveReminder() }
        }
        companionModel.onSnoozeAction = { [weak self] in
            MainActor.assumeIsolated { self?.snoozeActiveReminder() }
        }
    }

    // MARK: Engine events

    private func handle(_ event: ReminderEvent) {
        switch event {
        case .reminderDue(let kind, let message):
            pendingMessage = message
            stateMachine.handle(.summon(.reminder(kind)))

        case .reminderAcknowledged, .reminderSnoozed:
            stateMachine.handle(.reminderResolved)

        case .reminderTimedOut:
            // Nobody was there. Leave quietly.
            stateMachine.handle(.reminderResolved)

        case .waterLogged(let glasses, let goal, let goalJustReached):
            if goalJustReached {
                celebrate(catalog.nextGoalMessage(name: settings.userName))
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

        switch state {
        case .hidden:
            stopAnimation()
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
            applyClip(named: purpose == .greeting ? ClipName.wave : ClipName.happy)
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

        case .onBreak:
            applyClip(named: ClipName.eyeBreak)
            windowManager.setInteractive(true)
            startBreak()

        case .greeting:
            applyClip(named: ClipName.wave)
            companionModel.bubble = CompanionViewModel.Bubble(message: pendingMessage ?? "Hi 👋")
            pendingMessage = nil
            scheduleStateEvent(.animationFinished, after: configuration.greetingDuration)

        case .celebrating:
            applyClip(named: ClipName.happy)
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
            applyClip(named: kind.clipName)
            companionModel.bubble = CompanionViewModel.Bubble(
                message: pendingMessage ?? kind.displayName,
                primaryTitle: kind.acknowledgeTitle,
                showsSnooze: true
            )
            pendingMessage = nil
            // The only moment in the app's life when clicks do not pass through.
            windowManager.setInteractive(true)

        case .leaving:
            endBreak()
            companionModel.entranceProgress = 1
            applyClip(named: ClipName.walk)
            companionModel.bubble = nil
            windowManager.setInteractive(false)
            // Turn around: the walk-out is the walk-in clip, mirrored.
            facing = settings.corner.entryFacing == .right ? .left : .right
            companionModel.facing = facing
            let exit = entryOrigin()
            let duration = CharacterPlacement.walkDuration(
                from: windowManager.currentOrigin, to: exit, speed: configuration.walkingSpeed
            )
            windowManager.move(to: exit, duration: duration) { [weak self] in
                MainActor.assumeIsolated { _ = self?.stateMachine.handle(.exitedScreen) }
            }
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
        guard let kind = engine.activeReminder else { return }
        let startsBreak = kind == .eyeBreak && settings.dimsScreenOnBreak && settings.eyeBreakDuration > 0
        engine.acknowledge(kind)
        if startsBreak {
            // The engine has already scheduled the next cycle; now actually
            // hold the user to the break they just agreed to.
            stateMachine.handle(.breakStarted)
        }
    }

    private func snoozeActiveReminder() {
        guard let kind = engine.activeReminder else { return }
        engine.snooze(kind)
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

        let message = catalog.nextBreakStartMessage(name: settings.userName)
        updateBreakBubble(message: message, at: Date())

        breakTicker?.invalidate()
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let countdown = self.breakCountdown else { return }
                let now = Date()
                if countdown.isFinished(at: now) {
                    self.finishBreak()
                } else {
                    self.updateBreakBubble(message: message, at: now)
                }
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        breakTicker = ticker
    }

    private func updateBreakBubble(message: String, at now: Date) {
        guard let countdown = breakCountdown else { return }
        companionModel.bubble = CompanionViewModel.Bubble(
            message: "\(message)\n\(countdown.secondsRemaining(at: now))s",
            primaryTitle: "Skip",
            showsSnooze: false
        )
    }

    private func finishBreak() {
        endBreak()
        companionModel.bubble = CompanionViewModel.Bubble(
            message: catalog.nextBreakDoneMessage(name: settings.userName)
        )
        // She vanishes rather than walking off: the break ended because you
        // looked away, so a walk back across the screen would only pull your
        // eyes to it again. Fading out mirrors the pop-in she arrived with.
        vanish(after: configuration.greetingDuration)
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
        if dimmer.isDimmed { dimmer.undim(over: 0.5) }
    }

    /// Pops out to celebrate. Skipped while a reminder is being handled, so the
    /// celebration cannot interrupt the thing that earned it.
    private func celebrate(_ message: String) {
        guard engine.activeReminder == nil, !stateMachine.state.isWalking else {
            companionModel.bubble = CompanionViewModel.Bubble(message: message)
            return
        }
        pendingMessage = message
        stateMachine.handle(.summon(.celebration))
    }

    func triggerReminder(_ kind: ReminderKind) {
        engine.triggerNow(kind)
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

        if previous.characterHeight != newSettings.characterHeight {
            companionModel.characterHeight = newSettings.characterHeight
            windowManager.setSize(CompanionLayout.panelSize(characterHeight: newSettings.characterHeight))
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
        // Sample her colours so the thought cloud and buttons match the art.
        companionModel.palette = CharacterPaletteExtractor.palette(for: pack, cache: imageCache)
        applyClip(named: stateMachine.state.clipName)
    }

    private func applyClip(named name: String) {
        guard let pack,
              let clip = pack.resolveClip(named: name, wearingGlasses: settings.wearsGlasses)
        else {
            // No art at all: the view falls back to its vector placeholder.
            companionModel.image = nil
            companionModel.facing = facing
            return
        }
        sequencer.setClip(clip)
        companionModel.facing = facing
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
                self.engine.tick(idleSeconds: self.idleMonitor.idleSeconds)
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
                self.updateImage()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Keeps the animation running for as long as the character is visible.
    private func ensureAnimationMatchesVisibility() {
        stateMachine.state.isVisible ? startAnimation() : stopAnimation()
    }

    // MARK: Screen geometry

    private var panelSize: GSize {
        CompanionLayout.panelSize(characterHeight: settings.characterHeight)
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

    private func handleWake() {
        guard settings.greetOnWake, !settings.remindersPaused else { return }
        guard !settings.quietHours.contains(Date()) else { return }
        guard stateMachine.state == .hidden else { return }
        greet(catalog.nextWakeGreeting(for: Date(), name: settings.userName))
    }
}
