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

    /// - Parameter frameHeight: the rendered height of a character frame,
    ///   which exceeds `characterHeight` when the artwork carries headroom for
    ///   tall poses. Defaults to the character height for packs without a
    ///   manifest.
    public static func panelSize(characterHeight: Double, frameHeight: Double? = nil) -> GSize {
        let frame = frameHeight ?? characterHeight
        return GSize(
            width: max(minimumPanelWidth, frame * characterAspectRatio),
            height: frame + bubbleReservedHeight
        )
    }

    /// Gap between the character and her cloud.
    public static let cloudGap: Double = 8

    /// How far the cloud's near edge sits from the panel's anchored edge.
    ///
    /// Measured from what the *current pose* actually reaches rather than from
    /// the frame: a frame carries headroom only a jump ever uses, so anchoring
    /// the cloud to the frame left a 50-point gap above her head in every
    /// ordinary pose.
    public static func cloudDistance(headHeight: Double) -> Double {
        headHeight + cloudGap
    }

    /// How far to lift the character when she is anchored to the *top* of the
    /// panel instead of the bottom.
    ///
    /// Every frame carries transparent headroom above her so a jump has
    /// somewhere to go. Anchored to the bottom that headroom is invisible.
    /// Anchored to the top it lands between her head and the screen edge,
    /// leaving her floating tens of points below the corner she is meant to be
    /// tucked into -- and how far down depends on the pose, so she also drifts
    /// as clips change.
    ///
    /// Lifting by exactly the unused headroom pushes those transparent rows out
    /// through the top of the window. Nothing visible is clipped, the window
    /// does not have to move (moving it would put it over the menu bar, where
    /// an interactive panel would start eating clicks on system UI), and her
    /// top pixel ends up flush against the panel's top edge.
    public static func topAnchoredLift(frameHeight: Double, headHeight: Double) -> Double {
        max(0, frameHeight - headHeight)
    }
}
