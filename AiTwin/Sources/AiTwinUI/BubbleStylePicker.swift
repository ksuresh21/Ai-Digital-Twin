import SwiftUI
import AiTwinCore

/// Lets the user pick how messages are framed, showing each option as a real,
/// live preview rather than a name in a list.
///
/// The previews are the actual `SpeechBubbleView` at a reduced scale, not
/// pictures of it — so they use the current character's colours, and they can
/// never drift out of date when the drawing code changes.
public struct BubbleStylePicker: View {
    @Binding var selection: BubbleStyle
    let palette: CharacterPalette

    public init(selection: Binding<BubbleStyle>, palette: CharacterPalette) {
        self._selection = selection
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(BubbleStyle.allCases) { style in
                    BubbleStyleCard(
                        style: style,
                        palette: palette,
                        isSelected: style == selection
                    )
                    .onTapGesture { selection = style }
                }
            }
            Text(selection.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BubbleStyleCard: View {
    let style: BubbleStyle
    let palette: CharacterPalette
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // A neutral checkered-ish ground, so a transparent style is
                // visibly transparent rather than looking like a white box.
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.14))

                SpeechBubbleView(
                    message: "Water break 💧",
                    tailOnLeft: true,
                    palette: palette,
                    style: style
                )
                .scaleEffect(0.72)
                .allowsHitTesting(false)
            }
            .frame(height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(style.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
