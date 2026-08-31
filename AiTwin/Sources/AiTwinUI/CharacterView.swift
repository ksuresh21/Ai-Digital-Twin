import SwiftUI
import AppKit
import AiTwinCore
import AiTwinMac

/// Draws the current animation frame.
///
/// The one non-obvious line here is `.interpolation(.none)`. macOS smooths
/// images when it scales them, which turns a crisp 64x64 sprite into a blurry
/// smear the moment it is drawn at any other size -- including on a Retina
/// display, where everything is scaled by 2. Nearest-neighbour is mandatory for
/// pixel art, and forgetting it is the single most common way a pixel-art app
/// ends up looking wrong.
public struct CharacterView: View {
    let image: NSImage?
    let facing: Facing
    let height: Double
    /// 0 = absent, 1 = fully present. Drives the pop-in entrance.
    let entranceProgress: Double

    public init(image: NSImage?, facing: Facing, height: Double, entranceProgress: Double = 1) {
        self.image = image
        self.facing = facing
        self.height = height
        self.entranceProgress = entranceProgress
    }

    public var body: some View {
        Group {
            if let image {
                let style = RenderingStyle.forSource(pixelHeight: Int(image.size.height))
                Image(nsImage: image)
                    .resizable()
                    // Nearest-neighbour keeps true pixel art crisp, but would
                    // shred detailed artwork being scaled down. Chosen from the
                    // frame's own resolution -- see RenderingStyle.
                    .interpolation(style == .pixelArt ? .none : .high)
                    .antialiased(style != .pixelArt)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Shown when a pack has no usable art at all. A recognisable
                // placeholder beats an invisible window that looks like a bug.
                PlaceholderCharacter()
            }
        }
        .frame(height: height)
        // One walk cycle, mirrored. See Docs/ASSETS.md for why we do not ship
        // separate left and right art.
        .scaleEffect(x: facing.isMirrored ? -1 : 1, y: 1, anchor: .center)
        // Pop-in: rises and grows from her feet, so she looks like she stepped
        // up into place rather than being faded on by a compositor.
        .scaleEffect(0.55 + 0.45 * entranceProgress, anchor: .bottom)
        .opacity(entranceProgress)
        .offset(y: (1 - entranceProgress) * 10)
    }
}

/// A tiny vector stand-in used when no character frames could be loaded.
///
/// This is the last link in the error-handling chain from Section 16: even with
/// an empty Resources folder the app runs, and you can see that it is running.
struct PlaceholderCharacter: View {
    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.height / 16
            ZStack {
                RoundedRectangle(cornerRadius: unit)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: unit * 8, height: unit * 10)
                VStack(spacing: unit) {
                    HStack(spacing: unit * 2) {
                        Circle().fill(.white).frame(width: unit * 1.4, height: unit * 1.4)
                        Circle().fill(.white).frame(width: unit * 1.4, height: unit * 1.4)
                    }
                    Capsule().fill(.white.opacity(0.8)).frame(width: unit * 3, height: unit * 0.8)
                }
                .offset(y: -unit)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
