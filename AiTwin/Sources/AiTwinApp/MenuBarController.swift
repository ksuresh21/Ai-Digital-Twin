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
        let image: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png",
                                     subdirectory: "MenuBar"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
                  let loaded = NSImage(contentsOf: url) {
            image = loaded
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

        // Status
        menu.addItem(statusHeader())
        for kind in ReminderKind.allCases where settings.isEnabled(kind) {
            menu.addItem(countdownItem(for: kind))
        }

        // Water progress
        let log = coordinator.waterLog
        let waterItem = NSMenuItem(
            title: "Water today: \(log.glasses) / \(settings.dailyWaterGoal)",
            action: nil,
            keyEquivalent: ""
        )
        waterItem.isEnabled = false
        menu.addItem(waterItem)

        menu.addItem(.separator())

        let logWater = NSMenuItem(
            title: "I drank a glass  +1",
            action: #selector(logWaterTapped),
            keyEquivalent: "w"
        )
        logWater.target = self
        menu.addItem(logWater)

        let pause = NSMenuItem(
            title: settings.remindersPaused ? "Resume Reminders" : "Pause Reminders",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pause.target = self
        menu.addItem(pause)

        // Remind me now
        let remindNow = NSMenuItem(title: "Remind Me Now", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for kind in ReminderKind.allCases {
            let item = NSMenuItem(title: kind.displayName, action: #selector(triggerReminder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            submenu.addItem(item)
        }
        remindNow.submenu = submenu
        menu.addItem(remindNow)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit AiTwin", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// One line explaining why the app is or is not counting down. Without it,
    /// "quiet hours" and "you stepped away" look identical to "it broke".
    private func statusHeader() -> NSMenuItem {
        let title: String
        switch coordinator.holdReason {
        case .paused:     title = "Paused"
        case .quietHours: title = "Quiet hours — staying quiet"
        case .userIdle:   title = "You're away — timers on hold"
        case .none:       title = "Watching over you"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func countdownItem(for kind: ReminderKind) -> NSMenuItem {
        let remaining = coordinator.timeRemaining(for: kind)
        let title = "Next \(kind.displayName.lowercased()): \(Self.format(remaining))"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
