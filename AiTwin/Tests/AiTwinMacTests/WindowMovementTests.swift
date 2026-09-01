import AppKit
import Testing
import AiTwinCore
@testable import AiTwinMac

/// Movement tests that need a real window.
///
/// Everything else in this project is verified in Core against a fake clock,
/// which is far faster and far more reliable. These few exist because the bug
/// they guard against was invisible to that approach: the walk animation called
/// the public `setPosition`, which cancels a walk, so the first frame of every
/// walk cancelled the walk it belonged to. The maths was perfect; the window
/// still never moved.
@Suite("Window movement", .serialized)
@MainActor
struct WindowMovementTests {

    /// Runs the main run loop for `duration`, sampling where the window is.
    private func sampleWalk(_ manager: MacWindowManager, for duration: TimeInterval) -> [Int] {
        var samples: [Int] = []
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            samples.append(Int(manager.currentOrigin.x.rounded()))
        }
        return samples
    }

    @Test("a walk actually travels, and arrives")
    func walkTravels() {
        // The regression: this used to report two distinct positions, one pixel
        // apart, and never call its completion.
        let manager = MacWindowManager(size: GSize(width: 120, height: 200))
        manager.setContentView(NSView())
        manager.setPosition(GPoint(x: 0, y: 100))

        var arrived = false
        manager.move(to: GPoint(x: 200, y: 100), duration: 0.4) { arrived = true }

        let samples = sampleWalk(manager, for: 0.7)
        manager.hide()

        #expect(Set(samples).count > 5, "the window barely moved: \(Set(samples).sorted())")
        #expect(arrived, "the walk never completed")
        #expect(abs(manager.currentOrigin.x - 200) < 2)
    }

    @Test("setting a position abandons a walk in progress")
    func setPositionCancelsWalk() {
        // The other half of the same trade-off: anything summoned mid-exit must
        // not be dragged off screen by the walk it interrupted.
        let manager = MacWindowManager(size: GSize(width: 120, height: 200))
        manager.setContentView(NSView())
        manager.setPosition(GPoint(x: 0, y: 100))

        var arrived = false
        manager.move(to: GPoint(x: 500, y: 100), duration: 2) { arrived = true }
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))

        manager.setPosition(GPoint(x: 42, y: 100))
        _ = sampleWalk(manager, for: 0.3)
        manager.hide()

        #expect(manager.currentOrigin.x == 42, "the abandoned walk kept dragging the window")
        #expect(arrived == false, "an abandoned walk must not report arrival")
    }

    @Test("a zero-duration move jumps and completes immediately")
    func instantMove() {
        let manager = MacWindowManager(size: GSize(width: 120, height: 200))
        manager.setContentView(NSView())
        manager.setPosition(GPoint(x: 0, y: 0))

        var arrived = false
        manager.move(to: GPoint(x: 77, y: 0), duration: 0) { arrived = true }
        #expect(arrived)
        #expect(manager.currentOrigin.x == 77)
        manager.hide()
    }

    @Test("a second walk replaces the first rather than fighting it")
    func secondWalkWins() {
        let manager = MacWindowManager(size: GSize(width: 120, height: 200))
        manager.setContentView(NSView())
        manager.setPosition(GPoint(x: 0, y: 0))

        var firstArrived = false
        manager.move(to: GPoint(x: 400, y: 0), duration: 2) { firstArrived = true }
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))

        var secondArrived = false
        manager.move(to: GPoint(x: 60, y: 0), duration: 0.3) { secondArrived = true }
        _ = sampleWalk(manager, for: 0.6)
        manager.hide()

        #expect(secondArrived)
        #expect(firstArrived == false)
        #expect(abs(manager.currentOrigin.x - 60) < 2)
    }

    @Test("the panel is configured as a click-through, non-activating overlay")
    func panelConfiguration() {
        // The properties that make her a companion rather than an application.
        let manager = MacWindowManager(size: GSize(width: 120, height: 200))
        manager.setContentView(NSView())
        manager.show()
        defer { manager.hide() }

        manager.setInteractive(false)
        #expect(manager.ignoresMouseEventsForTesting)
        manager.setInteractive(true)
        #expect(manager.ignoresMouseEventsForTesting == false)
    }
}
