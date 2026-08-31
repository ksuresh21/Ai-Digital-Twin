import AppKit
import CoreGraphics
import AiTwinPlatform

/// Reports how long the user has been away from the keyboard and mouse.
///
/// Uses `CGEventSource.secondsSinceLastEventType`, which needs **no permissions
/// at all** -- unlike an event tap or anything under Accessibility, it only asks
/// the window server how long it has been since the last input event. That
/// matters for a small companion app: nothing in AiTwin should make macOS put up
/// a scary permission prompt.
public final class MacIdleMonitor: IdleMonitoring {

    public init() {}

    public var idleSeconds: TimeInterval {
        // ~0 is kCGAnyInputEventType: any keyboard, mouse or trackpad event.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
