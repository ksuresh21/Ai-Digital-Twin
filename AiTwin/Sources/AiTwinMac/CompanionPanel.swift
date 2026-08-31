import AppKit

/// The window the character lives in.
///
/// The choices here are the whole reason the app feels like a desktop companion
/// rather than an application, so each one is deliberate:
///
/// - **`NSPanel` with `.nonactivatingPanel`** -- the single most important
///   choice. A plain `NSWindow` activates its application when touched, which
///   would yank focus out of whatever you were typing in. A non-activating panel
///   never becomes the active app.
/// - **`.borderless`** -- no title bar, no traffic lights, no chrome.
/// - **`isOpaque = false` + a clear background + no shadow** -- the sprite is
///   drawn against nothing at all, instead of sitting on a grey rectangle.
/// - **`level = .statusBar` (25)** -- floats above ordinary windows and above
///   other floating utilities.
/// - **`.canJoinAllSpaces`** -- the character follows you between Spaces instead
///   of being abandoned on desktop 1.
/// - **`.stationary`** -- it does not slide around during Mission Control.
/// - **`.fullScreenAuxiliary`** -- lets it appear over a full-screen app. This
///   is the one behaviour Apple has changed between releases; see
///   Docs/MANUAL_TESTS.md, which asks you to verify it.
/// - **`ignoresMouseEvents = true`** by default -- clicks pass straight through
///   to whatever is underneath, so the character can never get in your way. It
///   is flipped to `false` only while a speech bubble with buttons is showing.
final class CompanionPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        // Keeps the panel out of the window menu, Exposé and screenshots' window
        // picker -- it is scenery, not a document.
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        // Without this the panel is released the first time it is ordered out
        // and the next show() would use freed memory.
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    /// A borderless window is refused key status by default, which would stop
    /// the bubble's buttons from responding. Allowed here, but note that the
    /// panel is non-activating -- becoming key does not make AiTwin the active
    /// application, so your frontmost app keeps its focus ring.
    override var canBecomeKey: Bool { true }

    /// Never the main window. AiTwin has no main window by design.
    override var canBecomeMain: Bool { false }
}
