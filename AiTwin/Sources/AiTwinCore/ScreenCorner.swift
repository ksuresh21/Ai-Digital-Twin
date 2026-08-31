import Foundation

/// Which corner of the screen the character walks to.
///
/// Version 1 ships `.bottomLeft` as the default (see `AiTwinSettings.defaults`),
/// but every corner is implemented and switchable from Settings -- the spec asks
/// for the position to be configurable rather than hard-coded.
public enum ScreenCorner: String, Codable, CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    public var displayName: String {
        switch self {
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        }
    }

    /// True when the character rests against the left edge, and therefore walks
    /// in from off-screen-left facing right.
    public var isLeft: Bool {
        self == .bottomLeft || self == .topLeft
    }

    public var isBottom: Bool {
        self == .bottomLeft || self == .bottomRight
    }

    /// The direction the character faces while walking *in* to this corner.
    public var entryFacing: Facing {
        isLeft ? .right : .left
    }
}

/// Which way the sprite is pointing.
///
/// We ship one walk cycle and mirror it horizontally for the other direction,
/// so the two directions can never drift out of visual sync. See Docs/ASSETS.md.
public enum Facing: String, Codable, Sendable {
    case left
    case right

    public var isMirrored: Bool { self == .left }
}
