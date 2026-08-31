import SwiftUI
import AiTwinCore

/// What the character is saying, in a pixel-art thought cloud.
///
/// Deliberately not an `NSAlert`, a notification, or anything with a title bar:
/// a modal dialog for "drink some water" is the opposite of calm. The cloud and
/// its buttons are drawn in the character's own colours -- the accent is sampled
/// from her artwork -- so the whole thing reads as part of her world rather than
/// a piece of system UI parked on the desktop.
public struct SpeechBubbleView: View {
    let message: String
    let primaryTitle: String?
    let onPrimary: (() -> Void)?
    let onSnooze: (() -> Void)?
    let tailOnLeft: Bool
    let palette: CharacterPalette
    let style: BubbleStyle

    public init(
        message: String,
        primaryTitle: String? = nil,
        onPrimary: (() -> Void)? = nil,
        onSnooze: (() -> Void)? = nil,
        tailOnLeft: Bool = true,
        palette: CharacterPalette = .fallback,
        style: BubbleStyle = .cloud
    ) {
        self.message = message
        self.primaryTitle = primaryTitle
        self.onPrimary = onPrimary
        self.onSnooze = onSnooze
        self.tailOnLeft = tailOnLeft
        self.palette = palette
        self.style = style
    }

    private var hasButtons: Bool { primaryTitle != nil && (onPrimary != nil || onSnooze != nil) }

    public var body: some View {
        let insets = PixelCloud.insets(for: style)

        VStack(spacing: 6) {
            messageText
            if hasButtons {
                HStack(spacing: 5) {
                    if let onPrimary, let primaryTitle {
                        Button(primaryTitle, action: onPrimary)
                            .buttonStyle(PixelButtonStyle(palette: palette, prominent: true))
                    }
                    if let onSnooze {
                        Button("Snooze", action: onSnooze)
                            .buttonStyle(PixelButtonStyle(palette: palette, prominent: false))
                    }
                }
            }
        }
        // Enough to clear the frame's edge, and no more -- the box should feel
        // small next to the character, not loom over her.
        .padding(.horizontal, insets.horizontal)
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
        .frame(minWidth: style.isFramed ? 120 : 90, maxWidth: 196)
        .background { PixelCloud(palette: palette, tailOnLeft: tailOnLeft, style: style) }
        .compositingGroup()
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
    }

    @ViewBuilder
    private var messageText: some View {
        let text = Text(message)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)

        if style.isFramed {
            // Ink, not `.primary`: the frame is always cream, so the text must
            // not flip to white in dark mode.
            text.foregroundStyle(Color(palette.ink))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Unframed: the text sits directly on the wallpaper, so it needs its
            // own outline to stay readable on a light or a dark background.
            text.foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: Color(palette.ink), radius: 0, x: 1, y: 1)
                .shadow(color: Color(palette.ink), radius: 0, x: -1, y: -1)
                .shadow(color: Color(palette.ink), radius: 0, x: 1, y: -1)
                .shadow(color: Color(palette.ink), radius: 0, x: -1, y: 1)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        }
    }
}

/// A chunky button that matches the cloud: flat fill, hard outline, no gloss.
///
/// The prominent variant uses the character's sampled accent colour, so the
/// action she is asking you to take is in *her* colour rather than the system
/// blue. That is most of what makes the reminder feel like her asking.
struct PixelButtonStyle: ButtonStyle {
    let palette: CharacterPalette
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill = prominent ? palette.accent : palette.paper.darkened(by: 0.06)
        let foreground = prominent ? palette.accentForeground : palette.ink

        configuration.label
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .circular)
                        .fill(Color(configuration.isPressed ? fill.darkened(by: 0.12) : fill))
                    RoundedRectangle(cornerRadius: 4, style: .circular)
                        .strokeBorder(Color(palette.ink), lineWidth: 1.5)
                }
            }
            .foregroundStyle(Color(foreground))
            // Presses push the button down a pixel instead of fading it -- the
            // kind of feedback the art style implies.
            .offset(y: configuration.isPressed ? 1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 4))
    }
}
