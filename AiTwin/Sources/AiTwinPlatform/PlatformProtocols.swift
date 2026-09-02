import Foundation
import AiTwinCore

/// The platform seam.
///
/// Everything the domain needs the operating system to do is expressed here as a
/// protocol, and nothing in this file imports AppKit. `AiTwinMac` supplies the
/// macOS implementations; a future Windows port would supply its own and reuse
/// `AiTwinCore` untouched. Keeping the seam this narrow is what makes that claim
/// credible rather than aspirational -- the seam is a handful of protocols, and
/// the domain depends on nothing else.
///
/// Not tested on Windows. No Windows implementation exists.

/// Describes one display.
public struct ScreenInfo: Equatable, Sendable {
    /// The full display bounds, in a bottom-left origin space.
    public let frame: GRect
    /// The area excluding the menu bar and the Dock. Placement uses this so the
    /// character is never hidden behind either.
    public let visibleFrame: GRect
    /// Stable identifier so a chosen display can be remembered across launches.
    public let identifier: String
    public let isPrimary: Bool

    public init(frame: GRect, visibleFrame: GRect, identifier: String, isPrimary: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.identifier = identifier
        self.isPrimary = isPrimary
    }
}

/// Supplies display geometry and tells the app when it changes.
public protocol ScreenProviding: AnyObject {
    var screens: [ScreenInfo] { get }
    /// The display the character should live on.
    var activeScreen: ScreenInfo? { get }
    /// Fires when a display is connected, disconnected, or resized, so the
    /// character can be re-anchored instead of stranded off screen.
    var onScreenConfigurationChange: (() -> Void)? { get set }
}

/// Owns the character's on-screen window.
///
/// Main-actor isolated because every window operation on every platform this is
/// likely to target must happen on the UI thread anyway; stating it here means
/// the compiler enforces it instead of the implementation hoping for it.
@MainActor
public protocol WindowManaging: AnyObject {
    func show()
    func hide()
    /// Moves the window instantly.
    func setPosition(_ origin: GPoint)
    /// Animates the window from its current position to `origin` over `duration`,
    /// calling `completion` when it arrives.
    func move(to origin: GPoint, duration: TimeInterval, completion: @escaping () -> Void)
    func setSize(_ size: GSize)
    /// Whether the window swallows clicks. False for almost all of the app's
    /// life, so clicks pass through to whatever is underneath.
    func setInteractive(_ interactive: Bool)
    var currentOrigin: GPoint { get }
}

/// Reports how long the user has been away from the keyboard and mouse.
public protocol IdleMonitoring: AnyObject {
    var idleSeconds: TimeInterval { get }
}

/// Tells the app when the user leaves the Mac and when they come back.
///
/// One protocol rather than separate "lock" and "wake" observers on purpose: a
/// lid close that also locks the screen produces four system notifications
/// across two notification centres, and only something that can see all of them
/// is able to turn that into exactly one leaving and one returning.
public protocol PresenceObserving: AnyObject {
    /// The screen locked, the screensaver started, or the machine slept.
    var onAway: (() -> Void)? { get set }
    /// The matching unlock or wake -- and only once *every* away signal has
    /// cleared, so waking a still-locked Mac does not count as coming back.
    var onBack: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Registers or unregisters the app as a login item.
public protocol LoginItemManaging: AnyObject {
    var isEnabled: Bool { get }
    /// Returns false if the request failed -- typically because the user has to
    /// approve it in System Settings.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
}

/// Loads character packs from disk.
public protocol CharacterPackLoading: AnyObject {
    /// Names of every pack available: the bundled one plus anything the user has
    /// installed.
    func availablePackNames() -> [String]
    /// Loads a pack, or nil if it has no usable frames.
    func loadPack(named name: String, frameDuration: TimeInterval) -> CharacterPack?
    /// Where user-installed packs go.
    var userPacksDirectory: URL { get }
}
