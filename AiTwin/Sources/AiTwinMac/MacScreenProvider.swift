import AppKit
import AiTwinCore
import AiTwinPlatform

/// Reports display geometry from `NSScreen`.
///
/// `NSScreen`'s coordinate space already matches Core's `GRect` convention
/// (origin bottom-left, +y up), so this is a straight translation with no
/// arithmetic -- all the placement maths lives in `CharacterPlacement`, where it
/// is unit-tested.
public final class MacScreenProvider: ScreenProviding {

    public var onScreenConfigurationChange: (() -> Void)?
    /// The display the user chose, by `NSScreen` identifier. Nil means "the one
    /// with the menu bar".
    public var preferredScreenIdentifier: String?

    private var observer: NSObjectProtocol?

    public init() {
        // Fired when a display is plugged in, unplugged, or its resolution or
        // Dock size changes. Without this the character can end up at
        // coordinates that no longer exist on any screen.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenConfigurationChange?()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var screens: [ScreenInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            ScreenInfo(
                frame: Self.rect(screen.frame),
                visibleFrame: Self.rect(screen.visibleFrame),
                identifier: Self.identifier(for: screen, fallbackIndex: index),
                isPrimary: index == 0
            )
        }
    }

    public var activeScreen: ScreenInfo? {
        let all = screens
        if let preferred = preferredScreenIdentifier,
           let match = all.first(where: { $0.identifier == preferred }) {
            return match
        }
        // NSScreen.main is the screen with the key window, which is the one the
        // user is working on -- a better default than "the primary display".
        if let main = NSScreen.main {
            let id = Self.identifier(for: main, fallbackIndex: 0)
            if let match = all.first(where: { $0.identifier == id }) { return match }
        }
        return all.first
    }

    private static func rect(_ rect: NSRect) -> GRect {
        GRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    /// `NSScreenNumber` is stable for a given display across connects; the index
    /// is only a fallback for the case where the key is unexpectedly absent.
    private static func identifier(for screen: NSScreen, fallbackIndex: Int) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "index-\(fallbackIndex)"
    }
}
