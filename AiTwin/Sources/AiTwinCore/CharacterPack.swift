import Foundation

/// A complete set of animations for one character.
///
/// Packs are just folders of PNGs (see Docs/ASSETS.md), so replacing the
/// character means dropping a folder into Application Support -- no rebuild, no
/// code change. That is the requirement behind "anyone can use their own
/// character".
public struct CharacterPack: Equatable, Sendable {
    public static let defaultPackName = "Default"

    public let name: String
    /// Clip name -> clip. May be missing entries; resolution handles that.
    public let clips: [String: AnimationClip]

    /// How much of each frame's height the standing character actually fills.
    ///
    /// Frames carry padding above the character so that poses reaching higher
    /// than standing -- arms overhead, a jump -- are not cut off. If the app
    /// scaled frames by their full height, that padding would shrink the
    /// character in every clip. Scaling by this fraction instead keeps her the
    /// same size no matter how much headroom the canvas needs.
    ///
    /// 1.0 for a pack with no manifest, which is the old behaviour.
    public let characterHeightFraction: Double

    /// Frame width divided by frame height. Needed to work out how wide the
    /// drawing actually is once it has been scaled to fit a panel, which the
    /// peek placement depends on.
    public let canvasAspectRatio: Double

    /// Where the peeking pose's pixels sit inside its canvas.
    ///
    /// Measured from the artwork at load time rather than read from
    /// `pack.json`, which carries vertical information only. Nil for a pack
    /// whose art could not be measured, in which case the peek falls back to
    /// aligning the panel itself — the old, slightly-inset behaviour.
    public let peekBounds: ClipBounds?

    /// A clip's horizontal extent, as fractions of its canvas width.
    public struct ClipBounds: Equatable, Sendable {
        /// Distance from the canvas's leading edge to the first visible pixel.
        public let leadingFraction: Double
        /// How much of the canvas width the visible pixels span.
        public let widthFraction: Double

        public init(leadingFraction: Double, widthFraction: Double) {
            self.leadingFraction = min(1, max(0, leadingFraction))
            self.widthFraction = min(1, max(0, widthFraction))
        }
    }

    public init(
        name: String,
        clips: [String: AnimationClip],
        characterHeightFraction: Double = 1,
        canvasAspectRatio: Double = CompanionLayout.characterAspectRatio,
        peekBounds: ClipBounds? = nil
    ) {
        self.name = name
        self.clips = clips
        self.characterHeightFraction = min(1, max(0.1, characterHeightFraction))
        self.canvasAspectRatio = max(0.05, canvasAspectRatio)
        self.peekBounds = peekBounds
    }

    /// The frame height needed for the character to measure `characterHeight`.
    public func frameHeight(forCharacterHeight characterHeight: Double) -> Double {
        characterHeight / characterHeightFraction
    }

    /// A pack is usable if it can draw the character standing still. Everything
    /// else has a fallback path to idle.
    public var isUsable: Bool {
        guard let idle = clips[ClipName.idle] else { return false }
        return !idle.isEmpty
    }

    /// Clips from the standard catalogue that this pack does not provide.
    /// Surfaced in Settings so a user can see what their art is missing rather
    /// than wondering why the character never drinks.
    public var missingClipNames: [String] {
        ClipName.all.filter { (clips[$0]?.isEmpty ?? true) }
    }

    /// Resolves a request for a clip, degrading rather than failing.
    ///
    /// Falls back to idle when a clip is absent, so a half-finished character
    /// pack still produces a working reminder -- she just stands there instead
    /// of the app failing.
    public func resolveClip(named name: String) -> AnimationClip? {
        nonEmptyClip(name) ?? nonEmptyClip(ClipName.idle)
    }

    private func nonEmptyClip(_ name: String) -> AnimationClip? {
        guard let clip = clips[name], !clip.isEmpty else { return nil }
        return clip
    }
}
