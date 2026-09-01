import Foundation

/// Pure geometry for "where does the character stand, and where does it walk in from".
///
/// This is deliberately free of AppKit so the four-corner math and the
/// screen-boundary clamping are unit-testable without ever opening a window.
/// `MacWindowManager` supplies the real `NSScreen.visibleFrame` and applies the
/// results; it contains no arithmetic of its own.
public enum CharacterPlacement {

    /// Where the character stands once it has finished walking in.
    ///
    /// - Parameters:
    ///   - corner: the configured resting corner.
    ///   - size: the on-screen size of the character window.
    ///   - visibleFrame: the screen's *visible* frame -- already excludes the
    ///     menu bar and the Dock, so the character never hides behind either.
    ///   - margin: breathing room between the sprite and the screen edge.
    public static func restingOrigin(
        corner: ScreenCorner,
        size: GSize,
        visibleFrame: GRect,
        margin: Double
    ) -> GPoint {
        let x = corner.isLeft
            ? visibleFrame.minX + margin
            : visibleFrame.maxX - size.width - margin
        let y = corner.isBottom
            ? visibleFrame.minY + margin
            : visibleFrame.maxY - size.height - margin
        return clamp(GPoint(x: x, y: y), size: size, to: visibleFrame)
    }

    /// Where the character starts its walk-in: fully off-screen, on the same
    /// side as its resting corner, at the resting height.
    public static func entryOrigin(
        corner: ScreenCorner,
        size: GSize,
        visibleFrame: GRect,
        margin: Double
    ) -> GPoint {
        let resting = restingOrigin(corner: corner, size: size, visibleFrame: visibleFrame, margin: margin)
        let x = corner.isLeft
            ? visibleFrame.minX - size.width
            : visibleFrame.maxX
        return GPoint(x: x, y: resting.y)
    }

    /// Keeps the character fully on screen.
    ///
    /// Called after every move and again whenever the display configuration
    /// changes, so unplugging a monitor relocates the character instead of
    /// stranding it at coordinates that no longer exist.
    public static func clamp(_ origin: GPoint, size: GSize, to visibleFrame: GRect) -> GPoint {
        // A screen smaller than the character would make the ranges invalid;
        // pin to the origin rather than produce NaN from a reversed range.
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return GPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }

    /// Where the character sits while peeking around the screen edge.
    ///
    /// Flush against the edge rather than at the resting corner: the peeking
    /// artwork is drawn hugging a vertical border, so it only reads correctly
    /// when that border coincides with the edge of the display. She is not
    /// standing anywhere — she is leaning in from off screen.
    /// - Parameter screenFrame: the display's *full* bounds. The peek hugs this
    ///   rather than the visible frame, so she appears at the literal edge of
    ///   the screen even when the Dock insets the usable area — leaning in from
    ///   a point 60 pixels inside the edge reads as hovering, not peeking.
    public static func peekOrigin(
        corner: ScreenCorner,
        size: GSize,
        visibleFrame: GRect,
        screenFrame: GRect? = nil
    ) -> GPoint {
        let edge = screenFrame ?? visibleFrame
        let x = corner.isLeft ? edge.minX : edge.maxX - size.width
        let y = corner.isBottom
            ? visibleFrame.minY
            : visibleFrame.maxY - size.height
        // Vertical still respects the visible frame so she never hides behind
        // the Dock or the menu bar; only the horizontal edge is absolute.
        let clampedY = min(max(y, visibleFrame.minY),
                           max(visibleFrame.minY, visibleFrame.maxY - size.height))
        return GPoint(x: x, y: clampedY)
    }

    /// Where the peek slides in from: the same height, just off screen, so the
    /// motion is a short lean rather than a walk across the desktop.
    public static func peekEntryOrigin(
        corner: ScreenCorner,
        size: GSize,
        visibleFrame: GRect,
        offset: Double,
        screenFrame: GRect? = nil
    ) -> GPoint {
        let resting = peekOrigin(corner: corner, size: size,
                                 visibleFrame: visibleFrame, screenFrame: screenFrame)
        return GPoint(x: resting.x + (corner.isLeft ? -offset : offset), y: resting.y)
    }

    /// How long a walk from `from` to `to` should take at `speed` points/second.
    public static func walkDuration(from: GPoint, to: GPoint, speed: Double) -> TimeInterval {
        guard speed > 0 else { return 0 }
        return abs(to.x - from.x) / speed
    }
}
