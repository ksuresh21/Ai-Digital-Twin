import SwiftUI
import AppKit
import AiTwinCore

/// What the companion panel should currently be showing.
///
/// The one piece of observable state between the coordinator and the view. The
/// coordinator pushes frames into it; the view only reads. Keeping the view
/// free of logic is what stops this project from turning into the giant
/// `ContentView.swift` the spec warns about.
@MainActor
public final class CompanionViewModel: ObservableObject {

    public struct Bubble: Equatable {
        public let message: String
        public let primaryTitle: String?
        public let showsSnooze: Bool

        public init(message: String, primaryTitle: String? = nil, showsSnooze: Bool = false) {
            self.message = message
            self.primaryTitle = primaryTitle
            self.showsSnooze = showsSnooze
        }

        public static func == (lhs: Bubble, rhs: Bubble) -> Bool {
            lhs.message == rhs.message
                && lhs.primaryTitle == rhs.primaryTitle
                && lhs.showsSnooze == rhs.showsSnooze
        }
    }

    @Published public var image: NSImage?
    @Published public var facing: Facing = .right
    @Published public var characterHeight: Double = 128
    /// Rendered height of a frame. Larger than `characterHeight` when the pack
    /// carries headroom for tall poses, so the character stays the same size.
    @Published public var frameHeight: Double = 128
    /// How far above the panel's bottom the current pose actually reaches.
    /// The cloud sits just above this, so it hugs her head in ordinary poses
    /// and lifts only for a jump or a reach.
    @Published public var headHeight: Double = 128
    @Published public var bubble: Bubble?
    /// A ticking clock shown inside the cloud, kept *out* of `Bubble` on
    /// purpose.
    ///
    /// It used to be part of the message. The cloud is keyed by its message so
    /// a new reminder animates in rather than silently swapping text -- which
    /// meant a countdown in the message changed the key once a second, and
    /// SwiftUI tore the cloud down and rebuilt it, replaying the scale-and-fade
    /// entrance every second. Held separately, only this label redraws.
    @Published public var countdown: String?
    /// Colours sampled from the current character, so the cloud and its buttons
    /// look like they belong to her.
    @Published public var palette: CharacterPalette = .fallback
    /// Which frame style the user picked in Settings.
    @Published public var bubbleStyle: BubbleStyle = .cloud
    /// 0 while off screen, 1 fully present. Drives the pop-in entrance.
    @Published public var entranceProgress: Double = 1
    /// True at a top corner. The character then sits against the *top* of the
    /// panel with the cloud below her, rather than the other way round -- the
    /// cloud's reserved space must be on the inward side, or it pushes her down
    /// away from the screen edge she is supposed to be tucked into.
    @Published public var anchorsToTop: Bool = false

    /// Set by the coordinator. The view calls these; it does not know what they do.
    public var onPrimaryAction: (() -> Void)?
    public var onSnoozeAction: (() -> Void)?

    public init() {}
}
