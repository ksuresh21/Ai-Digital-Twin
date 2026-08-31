import AppKit
import AiTwinCore
import AiTwinPlatform

/// Drives the companion panel: shows it, hides it, and walks it across the screen.
///
/// Walking is done with a `CVDisplayLink`-free, timer-driven interpolation
/// rather than `NSViewAnimation`, because the character's animation frames must
/// advance in step with its position -- a sprite that slides smoothly while its
/// legs animate at a different rate looks like it is ice-skating. One timer
/// drives both.
@MainActor
public final class MacWindowManager: NSObject, WindowManaging {

    private let panel: CompanionPanel
    private var moveTimer: Timer?
    private var moveStart: GPoint = GPoint(x: 0, y: 0)
    private var moveEnd: GPoint = GPoint(x: 0, y: 0)
    private var moveStartTime: CFTimeInterval = 0
    private var moveDuration: TimeInterval = 0
    private var moveCompletion: (() -> Void)?

    /// Frames per second for the walk interpolation. 60 is smooth without being
    /// expensive; the sprite itself still changes at 8fps.
    private let movementFrameRate: Double = 60

    public init(size: GSize) {
        panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        super.init()
    }

    /// The view drawing the character. Set once, at startup.
    public func setContentView(_ view: NSView) {
        panel.contentView = view
    }

    public var currentOrigin: GPoint {
        GPoint(x: panel.frame.origin.x, y: panel.frame.origin.y)
    }

    public func show() {
        // orderFrontRegardless, not orderFront: the latter is ignored when the
        // app is not active, and AiTwin is an accessory app that is essentially
        // never active.
        panel.orderFrontRegardless()
    }

    public func hide() {
        cancelMove()
        panel.orderOut(nil)
    }

    public func setPosition(_ origin: GPoint) {
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    }

    public func setSize(_ size: GSize) {
        var frame = panel.frame
        frame.size = NSSize(width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }

    /// Whether the panel accepts clicks.
    ///
    /// False for nearly all of the app's life. Turned on only while a reminder
    /// bubble with buttons is up, so the character is never something you have
    /// to click around.
    public func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
    }

    // MARK: Walking

    public func move(to origin: GPoint, duration: TimeInterval, completion: @escaping () -> Void) {
        cancelMove()

        guard duration > 0 else {
            setPosition(origin)
            completion()
            return
        }

        moveStart = currentOrigin
        moveEnd = origin
        moveDuration = duration
        moveStartTime = CACurrentMediaTime()
        moveCompletion = completion

        let timer = Timer(timeInterval: 1.0 / movementFrameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepMove() }
        }
        // .common so the walk does not freeze while a menu is open or a window
        // is being resized.
        RunLoop.main.add(timer, forMode: .common)
        moveTimer = timer
    }

    private func stepMove() {
        let elapsed = CACurrentMediaTime() - moveStartTime
        let progress = min(1, elapsed / moveDuration)
        // Linear, on purpose: an eased walk reads as sliding, because the leg
        // animation runs at a constant rate.
        let x = moveStart.x + (moveEnd.x - moveStart.x) * progress
        let y = moveStart.y + (moveEnd.y - moveStart.y) * progress
        setPosition(GPoint(x: x, y: y))

        if progress >= 1 {
            let completion = moveCompletion
            cancelMove()
            completion?()
        }
    }

    private func cancelMove() {
        moveTimer?.invalidate()
        moveTimer = nil
        moveCompletion = nil
    }
}
