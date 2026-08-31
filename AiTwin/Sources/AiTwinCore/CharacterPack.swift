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

    public init(name: String, clips: [String: AnimationClip]) {
        self.name = name
        self.clips = clips
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
    /// Order: the glasses variant if glasses are on and the art exists, then the
    /// plain clip, then idle. Returning idle for a missing `drink` clip means a
    /// half-finished character pack still produces a working reminder -- the
    /// character just stands there instead of crashing the app, which is exactly
    /// what Section 16 asks for.
    public func resolveClip(named name: String, wearingGlasses: Bool) -> AnimationClip? {
        if wearingGlasses, let variant = nonEmptyClip(ClipName.glassesVariant(of: name)) {
            return variant
        }
        if let exact = nonEmptyClip(name) {
            return exact
        }
        return nonEmptyClip(ClipName.idle)
    }

    private func nonEmptyClip(_ name: String) -> AnimationClip? {
        guard let clip = clips[name], !clip.isEmpty else { return nil }
        return clip
    }
}
