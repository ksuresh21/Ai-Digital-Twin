import SwiftUI
import AiTwinCore

/// The full contents of the companion panel.
///
/// The character is pinned to the bottom of the panel and the cloud is drawn
/// **outside the layout flow**, floating above her head. That is the fix for a
/// real bug: when the cloud was a sibling in a `VStack`, a tall message grew the
/// stack past the panel's height and pushed the character down -- shifting her
/// body, sometimes clipping her out of the window entirely, and making her
/// appear to rise as the cloud collapsed on the way out.
///
/// With the cloud in an overlay, its size cannot move her by even a pixel. A
/// message too tall for the panel now clips the cloud, which is the right thing
/// to sacrifice.
public struct CompanionOverlayView: View {
    @ObservedObject var model: CompanionViewModel

    public init(model: CompanionViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            CharacterView(
                image: model.image,
                facing: model.facing,
                height: model.characterHeight,
                entranceProgress: model.entranceProgress
            )

            if let bubble = model.bubble {
                SpeechBubbleView(
                    message: bubble.message,
                    primaryTitle: bubble.primaryTitle,
                    onPrimary: bubble.primaryTitle == nil ? nil : { model.onPrimaryAction?() },
                    onSnooze: bubble.showsSnooze ? { model.onSnoozeAction?() } : nil,
                    tailOnLeft: model.facing == .right,
                    palette: model.palette,
                    style: model.bubbleStyle
                )
                // Sits just above her head. Because this is an overlay, its own
                // height never feeds back into the character's position.
                .offset(y: -(model.characterHeight + 2))
                // Keyed by message so a new reminder animates in rather than
                // silently swapping its text.
                .id(bubble.message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.22), value: model.bubble)
        // Explicitly clear: the panel is transparent, and any background here
        // would reintroduce the opaque rectangle the whole design avoids.
        .background(Color.clear)
    }
}
