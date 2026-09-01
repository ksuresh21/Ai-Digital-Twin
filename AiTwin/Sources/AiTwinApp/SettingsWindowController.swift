import AppKit
import SwiftUI
import AiTwinCore
import AiTwinUI

/// Hosts the Settings window.
///
/// A plain `NSWindow` with an `NSHostingView`, rather than SwiftUI's `Settings`
/// scene, because AiTwin is an accessory app with no `App` scene tree to hang
/// one from. It is created lazily and kept around, so reopening it is instant
/// and returns you to the tab you were on.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    let model: SettingsViewModel

    init(model: SettingsViewModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "AiTwin Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        // An accessory app is never "active", so the Settings window would open
        // behind whatever you were using. Activating here is the one moment
        // AiTwin deliberately takes focus -- you asked for a window, so you get
        // it in front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
