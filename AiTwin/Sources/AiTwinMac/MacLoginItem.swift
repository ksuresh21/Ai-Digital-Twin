import AppKit
import ServiceManagement
import AiTwinPlatform

/// Registers AiTwin to start when you log in.
///
/// `SMAppService.mainApp` is the modern replacement for the deprecated
/// `SMLoginItemSetEnabled` and the long-obsolete login-items list. It requires a
/// properly bundled, signed `.app` -- running the raw executable from
/// `swift run` will fail here, which is expected and handled rather than fatal.
public final class MacLoginItem: LoginItemManaging {

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Common and non-fatal: the app is not bundled, or macOS wants the
            // user to approve it under System Settings > General > Login Items.
            NSLog("[AiTwin] Login item change failed: \(error.localizedDescription)")
            return false
        }
    }
}
