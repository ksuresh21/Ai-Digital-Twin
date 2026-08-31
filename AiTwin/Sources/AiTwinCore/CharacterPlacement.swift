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

    /// How long a walk from `from` to `to` should take at `speed` points/second.
    public static func walkDuration(from: GPoint, to: GPoint, speed: Double) -> TimeInterval {
        guard speed > 0 else { return 0 }
        return abs(to.x - from.x) / speed
    }
}
