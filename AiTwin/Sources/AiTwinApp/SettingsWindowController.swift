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

        // Become a normal app for as long as this window is open.
        //
        // As an accessory, AiTwin cannot hold activation: clicking any other app
        // dropped Settings behind it with no Dock icon and no ⌘-Tab entry to get
        // back, so the window looked like it had vanished. It also made
        // NSOpenPanel unreliable, because a modal file picker belongs to an app
        // that can actually be active.
        //
        // `.regular` puts a Dock icon and a real menu bar back for the duration.
        // `windowWillClose` returns us to `.accessory`, so the companion goes
        // back to being invisible the moment Settings is dismissed.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// True while Settings is on screen, so the delegate knows whether a file
    /// picker can be presented.
    var isOpen: Bool { window?.isVisible == true }

    func windowWillClose(_ notification: Notification) {
        // Straight back to a menu-bar-only app: no Dock icon, no ⌘-Tab entry.
        NSApp.setActivationPolicy(.accessory)
    }
}
