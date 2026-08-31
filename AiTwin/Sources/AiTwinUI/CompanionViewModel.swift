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
    @Published public var bubble: Bubble?
    /// Colours sampled from the current character, so the cloud and its buttons
    /// look like they belong to her.
    @Published public var palette: CharacterPalette = .fallback
    /// Which frame style the user picked in Settings.
    @Published public var bubbleStyle: BubbleStyle = .cloud
    /// 0 while off screen, 1 fully present. Drives the pop-in entrance.
    @Published public var entranceProgress: Double = 1

    /// Set by the coordinator. The view calls these; it does not know what they do.
    public var onPrimaryAction: (() -> Void)?
    public var onSnoozeAction: (() -> Void)?

    public init() {}
}
