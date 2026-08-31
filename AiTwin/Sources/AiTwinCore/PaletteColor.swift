import Foundation

/// A plain RGB colour, so Core can describe a palette without importing a UI
/// framework. `AiTwinUI` converts these to SwiftUI `Color`s.
public struct PaletteColor: Equatable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Perceived brightness, used to decide whether text on this colour should
    /// be dark or light. Coefficients are the standard luma weights -- green
    /// reads far brighter to the eye than blue at the same value.
    public var luminance: Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// HSV saturation. Used to find a character's signature colour: skin, hair
    /// and clothing are saturated, while outlines and shadows are not.
    public var saturation: Double {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        guard maxComponent > 0 else { return 0 }
        return (maxComponent - minComponent) / maxComponent
    }

    public var value: Double { max(red, green, blue) }

    /// Darkened toward black. Used for outlines and pressed states.
    public func darkened(by amount: Double) -> PaletteColor {
        let factor = 1 - min(1, max(0, amount))
        return PaletteColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    /// Lightened toward white.
    public func lightened(by amount: Double) -> PaletteColor {
        let t = min(1, max(0, amount))
        return PaletteColor(
            red: red + (1 - red) * t,
            green: green + (1 - green) * t,
            blue: blue + (1 - blue) * t
        )
    }
}

/// The colours a thought cloud and its buttons are drawn in.
///
/// `accent` is sampled from the character's own artwork so the buttons look
/// like they belong to her rather than to the operating system. Everything else
/// is fixed, because the cloud is meant to read as a painted prop in the
/// character's world, not as a system control that follows the OS theme.
public struct CharacterPalette: Equatable, Sendable {
    /// The character's signature colour. Buttons and the cloud's inner bevel.
    public let accent: PaletteColor
    /// Outlines and text.
    public let ink: PaletteColor
    /// The cloud's paper.
    public let paper: PaletteColor
    /// Small decorative sparkles.
    public let sparkle: PaletteColor

    public init(accent: PaletteColor, ink: PaletteColor, paper: PaletteColor, sparkle: PaletteColor) {
        self.accent = accent
        self.ink = ink
        self.paper = paper
        self.sparkle = sparkle
    }

    /// Used before a pack has loaded, and for packs with no usable colour.
    public static let fallback = CharacterPalette(
        accent: PaletteColor(hex: 0xF0B478),
        ink: PaletteColor(hex: 0x2A1A18),
        paper: PaletteColor(hex: 0xFDF9EE),
        sparkle: PaletteColor(hex: 0xB9AEE0)
    )

    /// Builds a palette around a sampled accent, keeping the rest fixed.
    public static func around(accent: PaletteColor) -> CharacterPalette {
        CharacterPalette(
            accent: accent,
            ink: fallback.ink,
            paper: fallback.paper,
            sparkle: fallback.sparkle
        )
    }

    /// Text colour that stays readable on the accent.
    public var accentForeground: PaletteColor {
        accent.luminance > 0.55 ? ink : PaletteColor(hex: 0xFFFFFF)
    }
}

/// Picks a character's signature colour out of a set of sampled pixels.
///
/// Kept in Core, and taking plain colours rather than an image, so the choice is
/// testable without decoding a PNG. `AiTwinMac` does the pixel reading.
public enum AccentPicker {
    /// Ignore near-greys: outlines, shadows and white highlights are not a
    /// character's signature colour.
    public static let minimumSaturation = 0.30
    /// Ignore near-black and near-white, which are almost always linework.
    public static let minimumValue = 0.40
    public static let maximumValue = 0.95

    /// Returns the most prominent sufficiently colourful shade, or nil.
    ///
    /// Scores by frequency, saturation *and* brightness. Frequency alone picks
    /// whatever the character has most of, which is usually shadow; adding the
    /// other two biases toward a shade vivid enough to put on a button, without
    /// letting a couple of bright pixels win outright.
    public static func pick(from samples: [PaletteColor]) -> PaletteColor? {
        guard !samples.isEmpty else { return nil }

        // Bucket into a coarse grid so near-identical shades count together.
        let levels = 8.0
        var buckets: [Int: (count: Int, sum: (Double, Double, Double))] = [:]
        for colour in samples {
            guard colour.saturation >= minimumSaturation,
                  colour.value >= minimumValue,
                  colour.value <= maximumValue else { continue }
            let r = Int(colour.red * levels), g = Int(colour.green * levels), b = Int(colour.blue * levels)
            let key = r * 100 + g * 10 + b
            var entry = buckets[key] ?? (0, (0, 0, 0))
            entry.count += 1
            entry.sum = (entry.sum.0 + colour.red, entry.sum.1 + colour.green, entry.sum.2 + colour.blue)
            buckets[key] = entry
        }
        guard !buckets.isEmpty else { return nil }

        var best: (score: Double, colour: PaletteColor)?
        for (_, entry) in buckets {
            let mean = PaletteColor(
                red: entry.sum.0 / Double(entry.count),
                green: entry.sum.1 / Double(entry.count),
                blue: entry.sum.2 / Double(entry.count)
            )
            let score = Double(entry.count) * (0.4 + mean.saturation) * (0.6 + 0.6 * mean.value)
            if best == nil || score > best!.score {
                best = (score, mean)
            }
        }
        return best?.colour
    }
}
