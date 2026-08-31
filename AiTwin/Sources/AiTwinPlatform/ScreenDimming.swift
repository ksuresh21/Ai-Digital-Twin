import Foundation

/// Dims every display for the duration of an eye break.
///
/// The reason this exists: a reminder you can dismiss in half a second does not
/// make anyone look away from their screen. Dimming does -- there is nothing to
/// read for twenty seconds, so you look at something else.
///
/// Deliberately **visual only**. It never captures clicks or keystrokes: an app
/// that locks you out of your Mac for twenty seconds is a liability in a meeting
/// or mid-deploy, and no health benefit justifies that.
@MainActor
public protocol ScreenDimming: AnyObject {
    /// Fades every display down to `opacity` (0...1) over `duration` seconds.
    func dim(to opacity: Double, over duration: TimeInterval)
    /// Fades back to normal.
    func undim(over duration: TimeInterval)
    var isDimmed: Bool { get }
}
