import AppKit
import AiTwinPlatform

/// Dims the displays by laying a translucent black window over each one.
///
/// This adjusts *apparent* brightness rather than the display's actual backlight
/// — changing real brightness needs private APIs, is not restorable if the app
/// crashes mid-break, and behaves badly on external monitors. An overlay is
/// honest, instantly reversible, and works the same on every display.
@MainActor
public final class MacScreenDimmer: ScreenDimming {

    private var windows: [NSWindow] = []
    public private(set) var isDimmed = false
    private var observer: NSObjectProtocol?

    public nonisolated init() {
        // Rebuild the overlays if a display is plugged in or unplugged mid-break,
        // so a newly attached screen does not stay bright.
        // nonisolated so the coordinator can construct one as a default argument.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDimmed else { return }
                let opacity = self.currentOpacity
                self.teardown()
                self.dim(to: opacity, over: 0)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private var currentOpacity: Double = 0

    public func dim(to opacity: Double, over duration: TimeInterval) {
        currentOpacity = min(1, max(0, opacity))
        if windows.isEmpty { build() }
        isDimmed = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for window in windows { window.animator().alphaValue = CGFloat(currentOpacity) }
        }
    }

    public func undim(over duration: TimeInterval) {
        guard !windows.isEmpty else { isDimmed = false; return }
        isDimmed = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for window in windows { window.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.teardown() }
        }
    }

    private func build() {
        teardown()
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .black
            window.isOpaque = false
            window.alphaValue = 0
            window.hasShadow = false
            // One level below the character, so she stays readable on top of
            // the dimming rather than being dimmed along with everything else.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            // Never intercept input. See the note on ScreenDimming.
            window.ignoresMouseEvents = true
            window.isExcludedFromWindowsMenu = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func teardown() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}
