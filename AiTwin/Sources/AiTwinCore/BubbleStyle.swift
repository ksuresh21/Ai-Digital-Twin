import Foundation

/// How the character's message is framed on screen.
///
/// Offered as a choice because this is the most visible piece of the app and
/// taste varies: some people want the pixel-art cloud, some want something that
/// disappears into the desktop. All of them are drawn on the same pixel grid, so
/// switching never changes the character's position or the panel's size.
public enum BubbleStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Lumpy pixel-art thought cloud with a stepped tail.
    case cloud
    /// Classic speech bubble: a pixel rounded rectangle with a pointed tail.
    case speech
    /// A plain pixel rounded rectangle. No tail, quietest of the framed styles.
    case rounded
    /// No frame at all -- just the text, outlined so it reads on any wallpaper.
    case plain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cloud:   return "Thought Cloud"
        case .speech:  return "Speech Bubble"
        case .rounded: return "Rounded"
        case .plain:   return "No Box"
        }
    }

    public var detail: String {
        switch self {
        case .cloud:   return "Lumpy pixel cloud with a tail"
        case .speech:  return "Classic bubble with a pointer"
        case .rounded: return "Simple rounded panel"
        case .plain:   return "Just the words, no frame"
        }
    }

    /// Whether the style draws a tail pointing back at the character.
    public var hasTail: Bool {
        self == .cloud || self == .speech
    }

    /// Whether the style paints a background the text has to clear.
    public var isFramed: Bool { self != .plain }
}
