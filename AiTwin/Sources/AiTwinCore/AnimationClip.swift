import Foundation

/// An ordered set of frames plus how to play them.
///
/// Frames are identified by *path*, not by loaded image, so the entire animation
/// model stays in Core with no image framework. `AiTwinMac` turns these paths
/// into `NSImage`s and caches them.
public struct AnimationClip: Equatable, Sendable {
    public let name: String
    public let framePaths: [String]
    public let frameDuration: TimeInterval
    public let loops: Bool

    /// Where this clip's artwork starts, as a fraction of the frame height from
    /// the top. Standing poses leave headroom (~0.19); a jump uses it all (0.0).
    ///
    /// The thought cloud is placed from this rather than from the frame height.
    /// Clearing the whole frame left a 50-point gap above her head in every
    /// ordinary pose, because the frame carries headroom that only a jump ever
    /// occupies. 0 for packs with no manifest, which clears everything.
    public let contentTopFraction: Double

    public init(
        name: String,
        framePaths: [String],
        frameDuration: TimeInterval,
        loops: Bool,
        contentTopFraction: Double = 0
    ) {
        self.name = name
        self.framePaths = framePaths
        self.frameDuration = frameDuration
        self.loops = loops
        self.contentTopFraction = min(0.9, max(0, contentTopFraction))
    }

    /// How far above the frame's bottom this clip's artwork reaches, when the
    /// frame is drawn `frameHeight` points tall.
    public func headHeight(inFrameOf frameHeight: Double) -> Double {
        frameHeight * (1 - contentTopFraction)
    }

    public var isEmpty: Bool { framePaths.isEmpty }
    public var frameCount: Int { framePaths.count }

    /// Total play time of one pass. Infinite-looping clips still report the
    /// length of a single cycle.
    public var cycleDuration: TimeInterval { Double(framePaths.count) * frameDuration }
}

/// Walks a clip forward in time and reports which frame should be on screen.
///
/// Driven by an explicit `advance(by:)` rather than owning a timer, for the same
/// reason the reminder engine takes a clock: a test can play a two-second
/// animation instantly, and the app can drive every sequencer from one shared
/// display tick instead of N competing timers.
public final class FrameSequencer {
    public private(set) var clip: AnimationClip
    public private(set) var currentIndex: Int = 0
    /// True once a non-looping clip has reached its final frame.
    public private(set) var isFinished: Bool = false

    private var elapsedInFrame: TimeInterval = 0

    public init(clip: AnimationClip) {
        self.clip = clip
        self.isFinished = clip.isEmpty
    }

    /// Swaps in a new clip and restarts from frame zero.
    ///
    /// Restarting is intentional: re-entering `walk` should begin the cycle, not
    /// resume it mid-stride from whenever it last stopped.
    public func setClip(_ clip: AnimationClip) {
        self.clip = clip
        currentIndex = 0
        elapsedInFrame = 0
        isFinished = clip.isEmpty
    }

    public var currentFramePath: String? {
        guard clip.framePaths.indices.contains(currentIndex) else { return nil }
        return clip.framePaths[currentIndex]
    }

    /// Advances the animation by `delta` seconds.
    ///
    /// Uses a while-loop rather than a single step so a delayed tick (the app was
    /// busy, the Mac woke from sleep) catches up correctly instead of dropping
    /// frames silently.
    public func advance(by delta: TimeInterval) {
        guard !clip.isEmpty, clip.frameDuration > 0, delta > 0 else { return }
        guard !(isFinished && !clip.loops) else { return }

        elapsedInFrame += delta
        // Compare with a tolerance rather than exactly. Repeatedly adding and
        // subtracting binary fractions drifts: eight advances of 0.01s sum to
        // slightly *under* 0.08, and without this the animation loses a frame
        // every few cycles and slowly desynchronises from the walk.
        let epsilon = clip.frameDuration * 1e-6
        while elapsedInFrame + epsilon >= clip.frameDuration {
            elapsedInFrame -= clip.frameDuration
            let next = currentIndex + 1
            if next < clip.frameCount {
                currentIndex = next
            } else if clip.loops {
                currentIndex = 0
            } else {
                // Hold the final frame. A finished wave should leave the
                // character with its hand up until the state machine moves on.
                currentIndex = clip.frameCount - 1
                isFinished = true
                elapsedInFrame = 0
                return
            }
        }
    }

    public func restart() {
        currentIndex = 0
        elapsedInFrame = 0
        isFinished = clip.isEmpty
    }
}
