import AppKit
import AiTwinCore

/// The menu bar item — AiTwin's only permanent piece of interface.
///
/// The app has no Dock icon and no main window, so this menu is how you reach
/// everything. It is rebuilt each time it opens (`menuNeedsUpdate`) rather than
/// kept in sync by a timer, because a countdown that only has to be right at the
/// instant you look at it does not deserve a timer.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.image?.accessibilityDescription = "AiTwin"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The Ai_Twin mark — the two facing heads — as a menu bar glyph.
    ///
    /// Loaded as a *template* image, which means macOS ignores its colours and
    /// tints it to match the menu bar. That is the only way an icon looks right
    /// in both light and dark mode, and while a menu is highlighted.
    ///
    /// Falls back to an SF Symbol if the asset is missing, so a stripped bundle
    /// still shows something clickable rather than an invisible status item.
    private static func menuBarIcon() -> NSImage? {
        // All three scales are loaded into one image, and this matters:
        // `NSImage(contentsOf:)` does *not* do the @2x/@3x file matching that
        // `NSImage(named:)` does for asset catalogues. Only the 1x file was ever
        // being read, so on a Retina display a 24x14 bitmap was stretched to
        // fill 14 points of a 2x bar -- a blurry icon, from files that were
        // sitting right there unused.
        let image: NSImage?
        let representations = ["", "@2x", "@3x"].compactMap { suffix -> NSImageRep? in
            guard let url = Bundle.main.url(
                forResource: "MenuBarIcon\(suffix)", withExtension: "png", subdirectory: "MenuBar"
            ) ?? Bundle.main.url(forResource: "MenuBarIcon\(suffix)", withExtension: "png")
            else { return nil }
            return NSImageRep(contentsOf: url)
        }

        if let base = representations.first {
            let combined = NSImage(size: NSSize(width: base.pixelsWide, height: base.pixelsHigh))
            representations.forEach(combined.addRepresentation)
            image = combined
        } else {
            image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "AiTwin")
        }
        // Fit the standard menu bar height; the status item scales nothing
        // itself. 14pt rather than 17 leaves visible air above and below the
        // glyph -- at 17 it filled the bar edge to edge and read as cropped.
        if let image, image.size.height > 0 {
            let height: CGFloat = 14
            image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        }
        image?.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = coordinator.currentSettings

        // Actions only. This menu used to open with five disabled info rows —
        // a status line, three countdowns and a water tally — which macOS greys
        // out because they are not clickable. Five grey lines before anything
        // you can press is a worse first impression than no information at all,
        // so the numbers moved into a Status item you can open when you want
        // them, and everything at this level does something.

        // Focus leads: it is the only item you open the menu specifically to
        // use. Everything below it is a small correction to what the app is
        // already doing on its own.
        if let focus = coordinator.focusSession {
            let stop = NSMenuItem(
                title: "End \(focus.phase.displayName) — \(focus.clockText(at: Date())) left",
                action: #selector(stopFocus), keyEquivalent: ""
            )
            stop.target = self
            menu.addItem(stop)

            let skip = NSMenuItem(title: "Skip to Next Phase", action: #selector(skipFocus), keyEquivalent: "")
            skip.target = self
            menu.addItem(skip)
        } else {
            let start = NSMenuItem(
                title: "Start Focus — \(Int(settings.focusSessionLength / 60)) min",
                action: #selector(startFocus), keyEquivalent: ""
            )
            start.target = self
            menu.addItem(start)
        }

        menu.addItem(.separator())

        let logWater = NSMenuItem(
            title: "I drank a glass  (\(settings.water.glassSize) ml)",
            action: #selector(logWaterTapped), keyEquivalent: ""
        )
        logWater.target = self
        menu.addItem(logWater)

        let pause = NSMenuItem(
            title: settings.remindersPaused ? "Resume Reminders" : "Pause Reminders",
            action: #selector(togglePause), keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        let remindNow = NSMenuItem(title: "Remind Me Now", action: nil, keyEquivalent: "")
        let remindMenu = NSMenu()
        for kind in ReminderKind.allCases where settings.isEnabled(kind) {
            let item = NSMenuItem(title: kind.displayName, action: #selector(triggerReminder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            remindMenu.addItem(item)
        }
        remindNow.submenu = remindMenu
        menu.addItem(remindNow)


        // The countdowns live behind this rather than sitting greyed out above
        // the actions. Open it and every row is live text, not disabled chrome.
        menu.addItem(.separator())
        let status = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
        status.submenu = statusMenu()
        menu.addItem(status)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit AiTwin", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    /// The numbers, on request. Every row here is enabled, so nothing is greyed:
    /// selecting one simply opens Settings where you can change it.
    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = coordinator.currentSettings

        let headline = coordinator.holdReason?.displayName ?? "Watching over you"
        let header = NSMenuItem(title: headline, action: #selector(openSettings), keyEquivalent: "")
        header.target = self
        menu.addItem(header)
        menu.addItem(.separator())

        for kind in ReminderKind.allCases where settings.isEnabled(kind) {
            let item = NSMenuItem(
                title: "Next \(kind.displayName.lowercased()) in \(Self.format(coordinator.timeRemaining(for: kind)))",
                action: #selector(openSettings), keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        let log = coordinator.waterLog
        let water = NSMenuItem(
            title: "Water today: \(settings.water.summary(glasses: log.glasses))",
            action: #selector(openSettings), keyEquivalent: ""
        )
        water.target = self
        menu.addItem(water)

        let streak = coordinator.currentStreak
        if streak > 0 {
            let item = NSMenuItem(
                title: "🔥 \(streak) day streak",
                action: #selector(openSettings), keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    static func format(_ interval: TimeInterval?) -> String {
        guard let interval else { return "—" }
        let total = Int(interval.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: Actions

    @objc private func togglePause() {
        coordinator.setPaused(!coordinator.currentSettings.remindersPaused)
    }

    @objc private func logWaterTapped() {
        coordinator.logWaterManually()
    }

    @objc private func triggerReminder(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ReminderKind(rawValue: raw) else { return }
        coordinator.triggerReminder(kind)
    }

    @objc private func startFocus() {
        coordinator.startFocusSession()
    }

    @objc private func stopFocus() {
        coordinator.stopFocusSession()
    }

    @objc private func skipFocus() {
        coordinator.skipFocusPhase()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
