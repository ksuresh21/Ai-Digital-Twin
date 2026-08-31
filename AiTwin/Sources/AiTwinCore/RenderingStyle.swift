import Foundation

/// How a character's frames should be scaled when drawn.
///
/// Nearest-neighbour is mandatory for true pixel art -- without it macOS blurs a
/// 64px sprite into a smear. But it is exactly wrong for the other common case:
/// artwork generated at 500-1000px, which the app then scales *down*. Nearest
/// neighbour downsampling throws away most of the pixels and produces jagged,
/// crawling edges, especially on hair and outlines.
///
/// So the rule is chosen from the source resolution rather than configured. A
/// pack authored as pixel art is small; a pack rendered by an image model is
/// large. Nothing for the user to get wrong.
public enum RenderingStyle: Equatable, Sendable {
    /// Nearest-neighbour. Hard pixel edges, no smoothing.
    case pixelArt
    /// High-quality interpolation. For detailed artwork being scaled down.
    case smooth

    /// Frames at or below this pixel height are treated as pixel art.
    ///
    /// 128 sits comfortably above the usual pixel-art canvases (32, 64, 96) and
    /// well below what an image generator produces (512 and up), so the
    /// classification is never a close call in practice.
    public static let pixelArtMaximumHeight = 128

    public static func forSource(pixelHeight: Int) -> RenderingStyle {
        pixelHeight <= pixelArtMaximumHeight ? .pixelArt : .smooth
    }
}
