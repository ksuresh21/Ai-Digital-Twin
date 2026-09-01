import AppKit
import Testing
import AiTwinCore
@testable import AiTwinMac

/// The eye break's dimming and its full-screen countdown.
///
/// These need real windows: the countdown lives in the dim overlay's own
/// `contentView`, and the property that matters -- that a tick changes only the
/// label's text and rebuilds nothing -- can only be checked against the actual
/// view objects.
@Suite("Screen dimming", .serialized)
@MainActor
struct ScreenDimmerTests {

    @Test("dimming covers every display and is reversible")
    func dimsAndUndims() {
        let dimmer = MacScreenDimmer()
        #expect(dimmer.isDimmed == false)
        dimmer.dim(to: 0.5, over: 0)
        #expect(dimmer.isDimmed)
        #expect(dimmer.windows.count == NSScreen.screens.count)
        for window in dimmer.windows {
            // Visual only: an app that swallows clicks for a minute is a
            // liability, so this must never intercept input.
            #expect(window.ignoresMouseEvents)
            #expect(window.level.rawValue < NSWindow.Level.statusBar.rawValue)
        }
        dimmer.undim(over: 0)
        #expect(dimmer.isDimmed == false)
    }

    @Test("the countdown appears on every display")
    func countdownOnEveryScreen() {
        let dimmer = MacScreenDimmer()
        dimmer.dim(to: 0.5, over: 0)
        dimmer.setCountdown("1:00", caption: BreakCountdown.overlayCaption)
        #expect(dimmer.countdownLabels.count == NSScreen.screens.count)
        for label in dimmer.countdownLabels {
            #expect(label.stringValue == "1:00")
            #expect(label.isHidden == false)
        }
        for label in dimmer.captionLabels {
            #expect(label.stringValue == BreakCountdown.overlayCaption)
        }
        dimmer.undim(over: 0)
    }

    @Test("a tick replaces the text and nothing else")
    func tickTouchesOnlyTheText() {
        let dimmer = MacScreenDimmer()
        dimmer.dim(to: 0.5, over: 0)
        dimmer.setCountdown("1:00", caption: BreakCountdown.overlayCaption)
        let before = dimmer.countdownLabels.map { ObjectIdentifier($0) }
        let font = dimmer.countdownLabels.first?.font

        for second in stride(from: 59, through: 50, by: -1) {
            dimmer.setCountdown(String(format: "0:%02d", second), caption: BreakCountdown.overlayCaption)
        }

        // Same label objects, same font: this is what makes the countdown calm
        // rather than a view being torn down and rebuilt once a second.
        #expect(dimmer.countdownLabels.map { ObjectIdentifier($0) } == before)
        #expect(dimmer.countdownLabels.first?.font == font)
        #expect(dimmer.countdownLabels.first?.stringValue == "0:50")
        dimmer.undim(over: 0)
    }

    @Test("the digits are monospaced so a centred clock cannot twitch")
    func digitsAreMonospaced() {
        let dimmer = MacScreenDimmer()
        dimmer.dim(to: 0.5, over: 0)
        dimmer.setCountdown("0:59", caption: nil)
        guard let label = dimmer.countdownLabels.first, let font = label.font else {
            Issue.record("no countdown label was built")
            return
        }
        let wide = ("1:11" as NSString).size(withAttributes: [.font: font]).width
        let narrow = ("0:00" as NSString).size(withAttributes: [.font: font]).width
        #expect(abs(wide - narrow) < 0.5)
        dimmer.undim(over: 0)
    }

    @Test("clearing the countdown hides it without tearing down the dimming")
    func clearingHidesTheLabels() {
        let dimmer = MacScreenDimmer()
        dimmer.dim(to: 0.5, over: 0)
        dimmer.setCountdown("0:20", caption: BreakCountdown.overlayCaption)
        dimmer.setCountdown(nil, caption: nil)
        #expect(dimmer.isDimmed)
        for label in dimmer.countdownLabels { #expect(label.isHidden) }
        for label in dimmer.captionLabels { #expect(label.isHidden) }
        dimmer.undim(over: 0)
    }

    @Test("the countdown is large enough to read from across the room")
    func countdownIsBig() {
        let dimmer = MacScreenDimmer()
        dimmer.dim(to: 0.5, over: 0)
        dimmer.setCountdown("1:00", caption: nil)
        guard let screen = NSScreen.main, let font = dimmer.countdownLabels.first?.font else {
            Issue.record("no screen or no label")
            return
        }
        // Comfortably bigger than any text in the character's cloud, which is
        // the whole reason the countdown moved out of it.
        #expect(font.pointSize >= min(180, screen.frame.height * 0.16) - 0.5)
        #expect(font.pointSize > 40)
        dimmer.undim(over: 0)
    }
}
