import Foundation

/// A source of "now".
///
/// Everything in AiTwinCore that cares about time asks a `Clock` instead of
/// calling `Date()` directly. That single indirection is what lets a test
/// advance a 40-minute eye-break in a microsecond instead of waiting for it.
public protocol Clock: AnyObject {
    var now: Date { get }
}

/// The real clock. Used by the running app.
public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
