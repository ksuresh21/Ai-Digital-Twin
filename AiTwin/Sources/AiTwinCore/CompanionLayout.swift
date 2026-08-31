import Foundation

/// How big the companion window needs to be.
///
/// The panel holds the sprite *and* the speech bubble above it, so it is taller
/// than the character. Kept here, in pure code, because placement depends on it
/// and placement is unit-tested: if this were computed inside the view, the
/// corner maths would be testing a size the app does not actually use.
public enum CompanionLayout {
    /// Width relative to height for the character's own box. Pixel-art
    /// characters are typically taller than they are wide.
    public static let characterAspectRatio: Double = 0.75
    /// Vertical space reserved above the character for the thought cloud.
    ///
    /// The cloud is drawn as an overlay, so exceeding this clips the cloud
    /// rather than moving the character -- but it should be generous enough
    /// that a two-line message with buttons fits comfortably.
    public static let bubbleReservedHeight: Double = 150
    /// Minimum panel width, so a bubble of text is not squeezed into a column.
    public static let minimumPanelWidth: Double = 240

    public static func panelSize(characterHeight: Double) -> GSize {
        GSize(
            width: max(minimumPanelWidth, characterHeight * characterAspectRatio),
            height: characterHeight + bubbleReservedHeight
        )
    }
}
