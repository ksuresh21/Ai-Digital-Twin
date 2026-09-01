import SwiftUI
import UniformTypeIdentifiers

/// Where a character pack gets dropped.
///
/// Drag-and-drop rather than only a file picker: a pack arrives as a zip in
/// Messages or a download, and dragging it straight onto the window is fewer
/// steps than saving it, opening a picker and navigating back to it. The picker
/// is still there for anyone who prefers it.
struct CharacterDropZone: View {
    @Binding var isTargeted: Bool
    let status: String?
    let onDrop: (URL) -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "person.crop.square.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text(isTargeted ? "Drop to install" : "Drag a character .zip or folder here")
                .font(.system(size: 12, weight: .medium))

            Button("Choose a File…", action: onBrowse)
                .buttonStyle(.link)
                .font(.caption)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.hasPrefix("Could not") ? .orange : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 4])
                        )
                }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { onDrop(url) }
            }
            return true
        }
    }
}
