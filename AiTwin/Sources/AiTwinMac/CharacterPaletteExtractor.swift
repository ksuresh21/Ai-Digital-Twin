import AppKit
import AiTwinCore

/// Samples a character's signature colour out of her artwork.
///
/// The pixel reading lives here because it needs `NSImage`; the *choice* of
/// which colour wins lives in `AccentPicker` in Core, where it is testable
/// without decoding a PNG.
public enum CharacterPaletteExtractor {

    /// Longest edge to downsample to before sampling.
    ///
    /// 128 rather than something smaller: downsampling blends edge pixels into
    /// partial transparency, and at 64px only a few hundred pixels survive the
    /// opacity filter -- few enough that the winning colour changed between
    /// frames. At 128 the result is stable.
    private static let sampleSize = 128

    /// Builds a palette from a pack's idle frame, falling back to the default
    /// warm palette if the art is missing or has no colourful area.
    @MainActor
    public static func palette(for pack: CharacterPack?, cache: FrameImageCache) -> CharacterPalette {
        guard let pack,
              let clip = pack.resolveClip(named: ClipName.idle, wearingGlasses: false),
              let path = clip.framePaths.first,
              let image = cache.image(at: path),
              let accent = accentColour(of: image)
        else { return .fallback }
        return .around(accent: accent)
    }

    /// Reads the opaque pixels of an image and asks Core which one is the
    /// character's signature colour.
    public static func accentColour(of image: NSImage) -> PaletteColor? {
        guard let bitmap = downsample(image) else { return nil }

        var samples: [PaletteColor] = []
        samples.reserveCapacity(bitmap.pixelsWide * bitmap.pixelsHigh)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                // Skip transparent and near-transparent pixels: the canvas
                // around the character is most of the image.
                guard colour.alphaComponent > 0.85 else { continue }
                samples.append(PaletteColor(
                    red: Double(colour.redComponent),
                    green: Double(colour.greenComponent),
                    blue: Double(colour.blueComponent)
                ))
            }
        }
        return AccentPicker.pick(from: samples)
    }

    private static func downsample(_ image: NSImage) -> NSBitmapImageRep? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = CGFloat(sampleSize) / longest
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
