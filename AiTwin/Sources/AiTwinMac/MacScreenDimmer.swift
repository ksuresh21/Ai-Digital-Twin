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

    // Internal rather than private: the dimming tests check the real windows
    // and the real labels, which is the only way to prove a tick rebuilds
    // nothing. See Tests/AiTwinMacTests/ScreenDimmerTests.swift.
    private(set) var windows: [NSWindow] = []
    /// The big digits and the line under them, one pair per display. Held so a
    /// tick can set `stringValue` and touch nothing else.
    private(set) var countdownLabels: [NSTextField] = []
    private(set) var captionLabels: [NSTextField] = []
    private var countdownText: String?
    private var captionText: String?
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
                let (count, caption) = (self.countdownText, self.captionText)
                self.teardown()
                self.dim(to: opacity, over: 0)
                self.setCountdown(count, caption: caption)
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

    public func setCountdown(_ text: String?, caption: String?) {
        countdownText = text
        captionText = caption
        let hidden = text == nil
        for label in countdownLabels {
            label.stringValue = text ?? ""
            label.isHidden = hidden
        }
        for label in captionLabels {
            label.stringValue = caption ?? ""
            label.isHidden = hidden || caption == nil
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
            addCountdownViews(to: window, screenSize: screen.frame.size)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func teardown() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
        captionLabels.removeAll()
    }

    /// Centres the countdown on one display.
    ///
    /// Sized as a fraction of the display so it reads the same on a laptop and
    /// on a 32-inch monitor, and set in monospaced digits: proportional digits
    /// change width as the numbers change, which makes a centred countdown
    /// twitch sideways every second.
    private func addCountdownViews(to window: NSWindow, screenSize: NSSize) {
        let content = NSView(frame: NSRect(origin: .zero, size: screenSize))
        content.wantsLayer = true

        let digitSize = min(180, max(64, screenSize.height * Self.countdownHeightFraction))
        let countdown = Self.label(
            font: .monospacedDigitSystemFont(ofSize: digitSize, weight: .ultraLight),
            alpha: 0.92
        )
        let caption = Self.label(
            font: .systemFont(ofSize: max(13, digitSize * 0.13), weight: .medium),
            alpha: 0.7
        )

        // Slightly above centre: dead centre reads as an error dialog, and it
        // is also where a video would be.
        let block = NSStackView(views: [countdown, caption])
        block.orientation = .vertical
        block.alignment = .centerX
        block.spacing = digitSize * 0.08
        block.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(block)
        NSLayoutConstraint.activate([
            block.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            block.centerYAnchor.constraint(equalTo: content.centerYAnchor,
                                           constant: screenSize.height * 0.06),
        ])

        window.contentView = content
        countdownLabels.append(countdown)
        captionLabels.append(caption)
        // Nothing to show until the first tick arrives.
        countdown.stringValue = countdownText ?? ""
        caption.stringValue = captionText ?? ""
        countdown.isHidden = countdownText == nil
        caption.isHidden = countdownText == nil || captionText == nil
    }

    /// The countdown's height as a fraction of the display's, so it is large
    /// enough to read from across the room without dominating a small screen.
    private static let countdownHeightFraction: Double = 0.16

    private static func label(font: NSFont, alpha: Double) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = font
        field.alignment = .center
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.backgroundColor = .clear
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        return field
    }
}
