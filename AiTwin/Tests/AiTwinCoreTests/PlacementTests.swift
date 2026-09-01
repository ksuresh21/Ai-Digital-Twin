import Foundation
import Testing
@testable import AiTwinCore

@Suite("Character placement")
struct CharacterPlacementTests {

    /// A 1440x900 screen whose visible frame excludes a 25pt menu bar and a
    /// 70pt Dock -- the shape of a real single-display Mac.
    private let visible = GRect(x: 0, y: 70, width: 1440, height: 805)
    private let size = GSize(width: 96, height: 128)
    private let margin: Double = 24

    @Test("bottom-left is the Version 1 default position")
    func bottomLeft() {
        let origin = CharacterPlacement.restingOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: margin
        )
        #expect(origin.x == 24)      // visible.minX + margin
        #expect(origin.y == 94)      // visible.minY + margin
    }

    @Test("bottom-right anchors to the right edge")
    func bottomRight() {
        let origin = CharacterPlacement.restingOrigin(
            corner: .bottomRight, size: size, visibleFrame: visible, margin: margin
        )
        #expect(origin.x == 1440 - 96 - 24)
        #expect(origin.y == 94)
    }

    @Test("top-left sits below the menu bar, not under it")
    func topLeft() {
        let origin = CharacterPlacement.restingOrigin(
            corner: .topLeft, size: size, visibleFrame: visible, margin: margin
        )
        #expect(origin.x == 24)
        #expect(origin.y == 875 - 128 - 24)   // visible.maxY - height - margin
        #expect(origin.y + size.height <= visible.maxY)
    }

    @Test("top-right anchors to both far edges")
    func topRight() {
        let origin = CharacterPlacement.restingOrigin(
            corner: .topRight, size: size, visibleFrame: visible, margin: margin
        )
        #expect(origin.x == 1440 - 96 - 24)
        #expect(origin.y == 875 - 128 - 24)
    }

    @Test("every corner keeps the character fully on screen")
    func allCornersStayOnScreen() {
        for corner in ScreenCorner.allCases {
            let origin = CharacterPlacement.restingOrigin(
                corner: corner, size: size, visibleFrame: visible, margin: margin
            )
            #expect(origin.x >= visible.minX)
            #expect(origin.y >= visible.minY)
            #expect(origin.x + size.width <= visible.maxX)
            #expect(origin.y + size.height <= visible.maxY)
        }
    }

    @Test("the walk-in starts fully off screen")
    func entryIsOffScreen() {
        let entry = CharacterPlacement.entryOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: margin
        )
        #expect(entry.x + size.width <= visible.minX)
    }

    @Test("the walk-in enters at the resting height")
    func entryMatchesRestingHeight() {
        let entry = CharacterPlacement.entryOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: margin
        )
        let resting = CharacterPlacement.restingOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: margin
        )
        // Walking in on a level path -- no drifting up or down the screen.
        #expect(entry.y == resting.y)
    }

    @Test("a right-hand corner enters from off screen right")
    func entryFromRight() {
        let entry = CharacterPlacement.entryOrigin(
            corner: .bottomRight, size: size, visibleFrame: visible, margin: margin
        )
        #expect(entry.x >= visible.maxX)
    }

    @Test("the character faces the direction it walks")
    func facing() {
        #expect(ScreenCorner.bottomLeft.entryFacing == .right)
        #expect(ScreenCorner.topLeft.entryFacing == .right)
        #expect(ScreenCorner.bottomRight.entryFacing == .left)
        #expect(ScreenCorner.topRight.entryFacing == .left)
    }

    @Test("a position off the right of the screen is pulled back on")
    func clampsRight() {
        let clamped = CharacterPlacement.clamp(GPoint(x: 5000, y: 100), size: size, to: visible)
        #expect(clamped.x == 1440 - 96)
    }

    @Test("a position off the bottom is pulled back on")
    func clampsBottom() {
        let clamped = CharacterPlacement.clamp(GPoint(x: 100, y: -500), size: size, to: visible)
        #expect(clamped.y == 70)
    }

    @Test("a stale position from a disconnected display is brought back on screen")
    func handlesDisplayDisconnect() {
        // The character was on a second 2560-wide display to the right; that
        // display is unplugged and only the built-in screen remains.
        let staleOrigin = GPoint(x: 3800, y: 1300)
        let clamped = CharacterPlacement.clamp(staleOrigin, size: size, to: visible)
        #expect(clamped.x + size.width <= visible.maxX)
        #expect(clamped.y + size.height <= visible.maxY)
        #expect(clamped.x >= visible.minX)
        #expect(clamped.y >= visible.minY)
    }

    @Test("a screen smaller than the character does not produce a bad position")
    func absurdlySmallScreen() {
        // Guards the reversed-range case that would otherwise produce NaN.
        let tiny = GRect(x: 0, y: 0, width: 50, height: 50)
        let clamped = CharacterPlacement.clamp(GPoint(x: 200, y: 200), size: size, to: tiny)
        #expect(clamped.x == 0)
        #expect(clamped.y == 0)
        #expect(clamped.x.isNaN == false)
    }

    @Test("walk duration follows distance over speed")
    func walkDuration() {
        let duration = CharacterPlacement.walkDuration(
            from: GPoint(x: 0, y: 0), to: GPoint(x: 180, y: 0), speed: 90
        )
        #expect(duration == 2.0)
    }

    @Test("a zero walking speed does not divide by zero")
    func zeroSpeed() {
        let duration = CharacterPlacement.walkDuration(
            from: GPoint(x: 0, y: 0), to: GPoint(x: 180, y: 0), speed: 0
        )
        #expect(duration == 0)
    }
}

@Suite("Quiet hours")
struct QuietHoursTests {

    @Test("a disabled window silences nothing")
    func disabled() {
        let hours = QuietHours(isEnabled: false, startMinutes: 0, endMinutes: 1439)
        #expect(hours.contains(minuteOfDay: 12 * 60) == false)
    }

    @Test("a same-day window matches inside it")
    func sameDayWindow() {
        let hours = QuietHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(hours.contains(minuteOfDay: 12 * 60))
        #expect(hours.contains(minuteOfDay: 8 * 60) == false)
        #expect(hours.contains(minuteOfDay: 18 * 60) == false)
    }

    @Test("the start is inclusive and the end exclusive")
    func boundaries() {
        let hours = QuietHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(hours.contains(minuteOfDay: 9 * 60))
        #expect(hours.contains(minuteOfDay: 17 * 60) == false)
    }

    @Test("a window crossing midnight matches on both sides of it")
    func crossesMidnight() {
        // The case a naive start <= t < end gets wrong.
        let hours = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(hours.contains(minuteOfDay: 23 * 60))
        #expect(hours.contains(minuteOfDay: 2 * 60))
        #expect(hours.contains(minuteOfDay: 0))
        #expect(hours.contains(minuteOfDay: 12 * 60) == false)
        #expect(hours.contains(minuteOfDay: 7 * 60) == false)
    }

    @Test("an empty window silences nothing rather than everything")
    func emptyWindow() {
        // A mis-set pair of sliders must not mute the app permanently.
        let hours = QuietHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 9 * 60)
        #expect(hours.contains(minuteOfDay: 9 * 60) == false)
        #expect(hours.contains(minuteOfDay: 3 * 60) == false)
    }
}

@Suite("Water log")
struct WaterLogTests {

    private let calendar = Calendar.testUTC
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a fresh log is empty")
    func startsEmpty() {
        #expect(WaterLog.empty(at: noon, calendar: calendar).glasses == 0)
    }

    @Test("adding a glass increments the count")
    func addsGlasses() {
        var log = WaterLog.empty(at: noon, calendar: calendar)
        log.add(at: noon, calendar: calendar)
        log.add(at: noon, calendar: calendar)
        #expect(log.glasses == 2)
    }

    @Test("the count resets on the next day")
    func resetsNextDay() {
        var log = WaterLog.empty(at: noon, calendar: calendar)
        log.add(3, at: noon, calendar: calendar)
        let tomorrow = noon.addingTimeInterval(24 * 3600)
        #expect(log.rolledOver(to: tomorrow, calendar: calendar).glasses == 0)
    }

    @Test("the count survives across the same day")
    func survivesSameDay() {
        var log = WaterLog.empty(at: noon, calendar: calendar)
        log.add(3, at: noon, calendar: calendar)
        let later = noon.addingTimeInterval(3600)
        #expect(log.rolledOver(to: later, calendar: calendar).glasses == 3)
    }

    @Test("a backwards clock correction resets rather than corrupts")
    func backwardsClock() {
        var log = WaterLog.empty(at: noon, calendar: calendar)
        log.add(3, at: noon, calendar: calendar)
        let yesterday = noon.addingTimeInterval(-24 * 3600)
        #expect(log.rolledOver(to: yesterday, calendar: calendar).glasses == 0)
    }

    @Test("goal progress is clamped at one")
    func progressClamped() {
        var log = WaterLog.empty(at: noon, calendar: calendar)
        log.add(20, at: noon, calendar: calendar)
        #expect(log.progress(WaterIntake(glassSize: 250, dailyGoal: 2000)) == 1.0)
    }

    @Test("water is counted in millilitres, not glasses")
    func countedInMillilitres() {
        // A glass is not a unit -- yours may be 200ml and mine 350ml -- so the
        // goal is a volume and the glass size is what converts it.
        let intake = WaterIntake(glassSize: 250, dailyGoal: 3000)
        #expect(intake.glassesForGoal == 12)
        #expect(intake.millilitres(forGlasses: 4) == 1000)
        #expect(intake.hasReachedGoal(glasses: 11) == false)
        #expect(intake.hasReachedGoal(glasses: 12))
    }

    @Test("a bigger glass means fewer of them")
    func biggerGlassFewerGlasses() {
        #expect(WaterIntake(glassSize: 200, dailyGoal: 3000).glassesForGoal == 15)
        #expect(WaterIntake(glassSize: 500, dailyGoal: 3000).glassesForGoal == 6)
    }

    @Test("a partial glass still counts as one more needed")
    func roundsUp() {
        // You cannot drink four fifths of a glass and call the day done.
        #expect(WaterIntake(glassSize: 250, dailyGoal: 2600).glassesForGoal == 11)
    }

    @Test("volumes read as litres once that is clearer")
    func formatting() {
        #expect(WaterIntake.format(millilitres: 750) == "750 ml")
        #expect(WaterIntake.format(millilitres: 3000) == "3 L")
        #expect(WaterIntake.format(millilitres: 2500) == "2.5 L")
    }

    @Test("absurd values are clamped rather than breaking the maths")
    func clamped() {
        #expect(WaterIntake(glassSize: 0, dailyGoal: 0).glassSize >= 50)
        #expect(WaterIntake(glassSize: 99999, dailyGoal: 99999).dailyGoal <= 10000)
        #expect(WaterIntake(glassSize: 250, dailyGoal: 250).progress(glasses: 0) == 0)
    }
}

@Suite("Companion layout")
struct CompanionLayoutTests {

    @Test("the panel reserves room above the character for the bubble")
    func panelIsTallerThanCharacter() {
        let size = CompanionLayout.panelSize(characterHeight: 128)
        #expect(size.height == 128 + CompanionLayout.bubbleReservedHeight)
    }

    @Test("the panel is never narrower than a readable bubble")
    func panelHasMinimumWidth() {
        let size = CompanionLayout.panelSize(characterHeight: 64)
        #expect(size.width == CompanionLayout.minimumPanelWidth)
    }

    @Test("a very large character widens the panel past the minimum")
    func largeCharacterWidensPanel() {
        let size = CompanionLayout.panelSize(characterHeight: 400)
        #expect(size.width == 300)
    }

    @Test("the panel still fits in a corner at the largest size")
    func largePanelStillFitsOnScreen() {
        let visible = GRect(x: 0, y: 70, width: 1440, height: 805)
        let size = CompanionLayout.panelSize(characterHeight: 256)
        for corner in ScreenCorner.allCases {
            let origin = CharacterPlacement.restingOrigin(
                corner: corner, size: size, visibleFrame: visible, margin: 24
            )
            #expect(origin.y + size.height <= visible.maxY)
            #expect(origin.x + size.width <= visible.maxX)
        }
    }
}

@Suite("Top-corner anchoring")
struct TopCornerTests {

    private let visible = GRect(x: 0, y: 70, width: 1440, height: 805)

    @Test("a top corner puts the character's edge against the screen edge")
    func topCornerIsFlush() {
        // The panel reserves space for the cloud. At a top corner that reserve
        // has to be *below* her, or it sits between her and the screen edge and
        // she hangs the height of the reserve too low.
        let frameHeight = 316.0
        let size = CompanionLayout.panelSize(characterHeight: 200, frameHeight: frameHeight)
        let origin = CharacterPlacement.restingOrigin(
            corner: .topLeft, size: size, visibleFrame: visible, margin: 24
        )
        // The panel's top edge is one margin below the top of the usable area…
        #expect(abs((origin.y + size.height) - (visible.maxY - 24)) < 0.5)
        // …and the character occupies that top portion, so her head is near it.
        let headroom = size.height - frameHeight
        #expect(headroom == CompanionLayout.bubbleReservedHeight)
    }

    @Test("bottom corners are unchanged")
    func bottomCornerUnchanged() {
        let size = CompanionLayout.panelSize(characterHeight: 200, frameHeight: 316)
        let origin = CharacterPlacement.restingOrigin(
            corner: .bottomLeft, size: size, visibleFrame: visible, margin: 24
        )
        #expect(origin.y == visible.minY + 24)
    }

    @Test("only the bottom corners anchor the character downward")
    func anchorDirection() {
        #expect(ScreenCorner.bottomLeft.isBottom)
        #expect(ScreenCorner.bottomRight.isBottom)
        #expect(ScreenCorner.topLeft.isBottom == false)
        #expect(ScreenCorner.topRight.isBottom == false)
    }

    @Test("a top-corner panel still fits entirely on screen")
    func topPanelFits() {
        let size = CompanionLayout.panelSize(characterHeight: 256, frameHeight: 405)
        for corner in [ScreenCorner.topLeft, .topRight] {
            let origin = CharacterPlacement.restingOrigin(
                corner: corner, size: size, visibleFrame: visible, margin: 24
            )
            #expect(origin.y >= visible.minY)
            #expect(origin.y + size.height <= visible.maxY)
        }
    }
}

/// Where the character actually lands at a *top* corner.
///
/// The earlier top-corner test only checked the panel's placement, which was
/// always right -- and the bug lived entirely in where she sat inside it. These
/// measure her topmost visible pixel instead.
@Suite("Top-corner anchoring")
struct TopCornerAnchoringTests {

    private let visible = GRect(x: 0, y: 70, width: 1440, height: 805)
    private let margin = 24.0

    /// Screen-space y of her topmost visible pixel at a top corner.
    ///
    /// Anchored to the panel's top edge, a frame's content begins
    /// `frameHeight - headHeight` further down, because the artwork is aligned
    /// to the frame's baseline and the space above it is transparent headroom
    /// for jumps. The lift is subtracted from exactly that.
    private func headTop(frameHeight: Double, headHeight: Double, lifted: Bool = true) -> Double {
        let size = CompanionLayout.panelSize(characterHeight: 200, frameHeight: frameHeight)
        let origin = CharacterPlacement.restingOrigin(
            corner: .topLeft, size: size, visibleFrame: visible, margin: margin
        )
        let panelTop = origin.y + size.height
        let lift = lifted
            ? CompanionLayout.topAnchoredLift(frameHeight: frameHeight, headHeight: headHeight)
            : 0
        return panelTop - ((frameHeight - headHeight) - lift)
    }

    @Test("her head sits one margin below the top of the usable screen")
    func headIsFlushWithTheCorner() {
        let top = headTop(frameHeight: 316, headHeight: 232)
        #expect(abs(top - (visible.maxY - margin)) < 0.5)
    }

    @Test("the pose no longer changes how low she hangs")
    func noDriftBetweenPoses() {
        // An idle, a reach and a full jump use different amounts of the frame.
        let tops = [232.0, 280.0, 316.0].map { headTop(frameHeight: 316, headHeight: $0) }
        #expect(Set(tops).count == 1)
    }

    @Test("unlifted, she hung lower the shorter the pose -- the original bug")
    func withoutTheLiftSheDrifts() {
        let idle = headTop(frameHeight: 316, headHeight: 232, lifted: false)
        let jump = headTop(frameHeight: 316, headHeight: 316, lifted: false)
        #expect(jump - idle == 84)
        #expect(idle < visible.maxY - margin)
    }

    @Test("the lift is exactly the frame's unused headroom")
    func liftEqualsUnusedHeadroom() {
        #expect(CompanionLayout.topAnchoredLift(frameHeight: 316, headHeight: 232) == 84)
        #expect(CompanionLayout.topAnchoredLift(frameHeight: 316, headHeight: 316) == 0)
    }

    @Test("a pose taller than its own frame is never pushed off the top")
    func liftNeverNegative() {
        #expect(CompanionLayout.topAnchoredLift(frameHeight: 200, headHeight: 260) == 0)
    }

    @Test("the cloud keeps the same distance from her whichever way up she is")
    func cloudDistanceIsSymmetric() {
        #expect(CompanionLayout.cloudDistance(headHeight: 232) == 232 + CompanionLayout.cloudGap)
        #expect(CompanionLayout.cloudGap > 0)
    }

    @Test("the cloud still fits in the reserve once she is lifted")
    func cloudFitsBelowHer() {
        // Lifted, her feet are `headHeight` below the panel top and the cloud
        // goes just under them -- it has to land inside the panel, not past it.
        let frameHeight = 316.0
        let size = CompanionLayout.panelSize(characterHeight: 200, frameHeight: frameHeight)
        for headHeight in [232.0, 280.0, frameHeight] {
            #expect(CompanionLayout.cloudDistance(headHeight: headHeight) < size.height)
        }
    }
}
