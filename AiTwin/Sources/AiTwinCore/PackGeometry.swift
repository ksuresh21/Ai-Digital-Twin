import Foundation

/// Where a frame's artwork sits inside its image.
public struct FrameBounds: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Bounding box of the non-transparent pixels.
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int

    public init(width: Int, height: Int, left: Int, top: Int, right: Int, bottom: Int) {
        self.width = width
        self.height = height
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public var contentWidth: Int { max(0, right - left) }
    public var contentHeight: Int { max(0, bottom - top) }
    public var isEmpty: Bool { contentWidth == 0 || contentHeight == 0 }
}

/// How one frame should be scaled and placed on the shared canvas.
public struct FramePlacement: Equatable, Sendable {
    public let scale: Double
    public let offsetX: Int
    public let offsetY: Int

    public init(scale: Double, offsetX: Int, offsetY: Int) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

/// The layout a whole pack should be rendered to.
public struct PackLayout: Equatable, Sendable {
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let characterHeight: Int
    public let baseline: Int
    /// Clip name -> the transform for every frame in that clip.
    public let placements: [String: FramePlacement]
    /// Clip name -> where its art starts, as a fraction of the canvas height.
    public let clipTopFractions: [String: Double]

    public init(
        canvasWidth: Int, canvasHeight: Int, characterHeight: Int, baseline: Int,
        placements: [String: FramePlacement], clipTopFractions: [String: Double]
    ) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.characterHeight = characterHeight
        self.baseline = baseline
        self.placements = placements
        self.clipTopFractions = clipTopFractions
    }
}

/// Works out how to lay a character pack onto one consistent canvas.
///
/// This is the part of importing that has caused every sizing problem so far, so
/// it lives here as pure arithmetic over measured bounds — no image decoding, no
/// file system — and is tested directly. `AiTwinMac` measures the pixels and
/// applies the result.
///
/// The rules, in order of how much trouble each one has caused:
///
/// 1. **One scale per clip, never per frame.** Scaling frames individually
///    flattens the motion they exist to show: a walk stops bobbing, an idle
///    stops breathing.
/// 2. **Align by the clip's lowest point**, so every clip stands on one floor.
/// 3. **Size the canvas by each clip's full top-to-bottom reach**, not its
///    height. A jump leaves the ground, so it sits higher than its height
///    suggests, and sizing by height guillotined exactly those frames.
/// 4. **Scale down rather than clip.** Losing a few percent of size is always
///    better than losing her hands.
public enum PackGeometry {

    /// Space left below the feet and above the tallest reach.
    public static let bottomMargin = 16
    public static let topMargin = 14
    public static let minimumCanvasWidth = 320
    public static let minimumCanvasHeight = 512

    /// Relative height for clips that are not a plain standing pose.
    ///
    /// The importer cannot tell a seated pose from a standing one, and getting
    /// it wrong is very visible, so the few exceptions are named. Anything not
    /// listed is treated as standing.
    public static let defaultHeightRatios: [String: Double] = [
        ClipName.focus: 0.86,     // seated: floor-to-head is shorter than standing
        ClipName.sitting: 0.86,
        ClipName.peek: 0.62,      // head and torso leaning round an edge
        ClipName.stretch: 1.16,   // both arms straight overhead
        ClipName.yawn: 1.16,      // one arm raised, and a lot of hair above
        ClipName.concerned: 1.14, // more hair volume than the standing poses
    ]

    /// Clips pinned to the canvas edge instead of centred on the floor.
    public static let edgeAligned: Set<String> = [ClipName.peek]

    /// Computes the layout for a pack.
    ///
    /// - Parameters:
    ///   - bounds: clip name -> measured bounds of each of its frames.
    ///   - characterHeight: target height of the standing character, in pixels.
    ///   - ratios: per-clip height hints; `defaultHeightRatios` when omitted.
    public static func layout(
        for bounds: [String: [FrameBounds]],
        characterHeight: Int = 470,
        ratios: [String: Double]? = nil
    ) -> PackLayout {
        let hints = ratios ?? defaultHeightRatios
        var scales: [String: Double] = [:]
        var extents: [String: (top: Int, bottom: Int, left: Int, right: Int)] = [:]

        for (clip, frames) in bounds {
            let usable = frames.filter { !$0.isEmpty }
            guard !usable.isEmpty else { continue }
            let height = usable.map(\.contentHeight).max() ?? 1
            guard height > 0 else { continue }
            let ratio = hints[clip] ?? 1.0
            scales[clip] = (Double(characterHeight) * ratio) / Double(height)
            extents[clip] = (
                top: usable.map(\.top).min() ?? 0,
                bottom: usable.map(\.bottom).max() ?? 0,
                left: usable.map(\.left).min() ?? 0,
                right: usable.map(\.right).max() ?? 0
            )
        }
        guard !scales.isEmpty else {
            return PackLayout(canvasWidth: minimumCanvasWidth, canvasHeight: minimumCanvasHeight,
                              characterHeight: characterHeight, baseline: minimumCanvasHeight - bottomMargin,
                              placements: [:], clipTopFractions: [:])
        }

        // Rule 3: the canvas must fit each clip's full reach.
        let tallestReach = scales.compactMap { clip, scale -> Double? in
            guard let e = extents[clip] else { return nil }
            return Double(e.bottom - e.top) * scale
        }.max() ?? Double(characterHeight)

        var canvasHeight = max(minimumCanvasHeight, Int(tallestReach) + bottomMargin + topMargin)
        canvasHeight += canvasHeight % 2
        let baseline = canvasHeight - bottomMargin

        // Rule 4: anything that still would not fit gets smaller, not cropped.
        for (clip, scale) in scales {
            guard let e = extents[clip] else { continue }
            let reach = Double(e.bottom - e.top) * scale
            let available = Double(baseline - topMargin)
            if reach > available { scales[clip] = scale * (available / reach) }
        }

        let widest = scales.compactMap { clip, scale -> Double? in
            guard let e = extents[clip] else { return nil }
            return Double(e.right - e.left) * scale
        }.max() ?? Double(minimumCanvasWidth)
        var canvasWidth = max(minimumCanvasWidth, Int(widest) + 32)
        canvasWidth += canvasWidth % 2

        var placements: [String: FramePlacement] = [:]
        var tops: [String: Double] = [:]
        for (clip, scale) in scales {
            guard let e = extents[clip] else { continue }
            let centreX = Double(e.left + e.right) / 2
            let offsetX = edgeAligned.contains(clip)
                ? Int((-Double(e.left) * scale).rounded())
                : Int((Double(canvasWidth) / 2 - centreX * scale).rounded())
            let offsetY: Int
            if edgeAligned.contains(clip) {
                // Pinned to head height rather than the floor: a peeking head
                // standing on the baseline would look like it was on the ground.
                let headLine = Double(baseline - characterHeight)
                offsetY = Int((headLine - Double(e.bottom - (e.bottom - e.top)) * scale).rounded())
            } else {
                offsetY = Int((Double(baseline) - Double(e.bottom) * scale).rounded())
            }
            placements[clip] = FramePlacement(scale: scale, offsetX: offsetX, offsetY: offsetY)
            let topOnCanvas = Double(offsetY) + Double(e.top) * scale
            tops[clip] = max(0, min(0.9, topOnCanvas / Double(canvasHeight)))
        }

        return PackLayout(
            canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            characterHeight: characterHeight, baseline: baseline,
            placements: placements, clipTopFractions: tops
        )
    }
}
