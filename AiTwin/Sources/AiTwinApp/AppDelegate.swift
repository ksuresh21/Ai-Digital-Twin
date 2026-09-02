import AppKit
import UniformTypeIdentifiers
import AiTwinCore
import AiTwinUI

/// Assembles the application and owns its top-level objects.
///
/// Everything is constructed here and injected downward. Nothing in the app
/// reaches for a singleton, which is what makes the whole domain testable.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var coordinator: AppCoordinator!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController!
    private var settingsModel: SettingsViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: menu bar only. No Dock icon, no ⌘-Tab entry, no menu bar
        // of its own. This is what makes AiTwin feel like part of the desktop
        // rather than an application you have open.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.buildMainMenu()

        let store = UserDefaultsSettingsStore()
        coordinator = AppCoordinator(settingsStore: store)

        settingsModel = SettingsViewModel(settings: coordinator.currentSettings)
        settingsWindow = SettingsWindowController(model: settingsModel)
        menuBar = MenuBarController(coordinator: coordinator)

        wire()
        coordinator.start()
        refreshSettingsModel()
        presentFirstRunIfNeeded()
    }

    /// On the very first launch, open Settings so the name and intervals can be
    /// set immediately -- an accessory app with no Dock icon is otherwise hard
    /// to find, and "where did it go?" is a bad first impression.
    private func presentFirstRunIfNeeded() {
        guard !coordinator.currentSettings.hasCompletedFirstRun else { return }
        var updated = coordinator.currentSettings
        updated.hasCompletedFirstRun = true
        coordinator.apply(updated)

        // After the greeting, so the character introduces herself first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.refreshSettingsModel()
            self?.settingsWindow.show()
        }
    }

    /// Launching an app that is already running sends a reopen event rather
    /// than starting a second copy. Without this, double-clicking AiTwin when it
    /// was already in the menu bar did nothing visible, which reads as a failure
    /// to launch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.greetOnDemand()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    /// Catches every route out of the app -- ⌘Q, the app menu, the Dock icon
    /// while Settings is open -- so the confirmation cannot be bypassed by
    /// quitting a different way.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmedQuit ? .terminateNow : askAboutQuitting()
    }

    /// True once the user has said yes, so the alert is not shown twice.
    private var confirmedQuit = false

    /// The menu-bar Quit item.
    private func confirmQuit() {
        guard !confirmedQuit else { return NSApp.terminate(nil) }
        if askAboutQuitting() == .terminateNow {
            NSApp.terminate(nil)
        }
    }

    /// Asks, and reports back what should happen.
    ///
    /// Quitting is easy to do by accident -- ⌘Q is next to ⌘W, and a menu-bar
    /// app that vanishes silently is one you assume has crashed. It also stops
    /// every reminder, so it deserves the one alert this app shows.
    private func askAboutQuitting() -> NSApplication.TerminateReply {
        // The alert needs a real app to sit in front of, and an accessory app
        // cannot hold activation.
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Quit AiTwin?"
        alert.informativeText = "Your reminders stop until you open it again. "
            + "Your history is saved and will still be here."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        let quit = alert.runModal() == .alertFirstButtonReturn

        // Put the policy back if they changed their mind, or the app would sit
        // in the Dock with no window for the rest of the session.
        if wasAccessory, !quit, !settingsWindow.isOpen {
            NSApp.setActivationPolicy(.accessory)
        }
        confirmedQuit = quit
        return quit ? .terminateNow : .terminateCancel
    }

    /// The menu bar shown while Settings is open.
    ///
    /// AiTwin had no main menu at all. That is invisible for a menu-bar app
    /// that never activates -- but opening Settings *does* activate it, and the
    /// menu bar then went blank apart from our own status icon, which looks
    /// broken. Worse, without an Edit menu macOS routes no editing commands, so
    /// ⌘C, ⌘V, ⌘A and ⌘Z did nothing in the name field.
    ///
    /// Deliberately minimal: an app menu, the editing commands text fields need,
    /// and a Window menu so ⌘W closes Settings. No File menu -- AiTwin has no
    /// documents, and an empty File menu is worse than none.
    private static func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "AiTwin")
        appMenu.addItem(
            withTitle: "About AiTwin",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        // ⌘, is where every Mac user looks for settings.
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit AiTwin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimise",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }

    /// Backs ⌘, in the app menu. The status-bar menu has its own path.
    @objc private func openSettingsFromMenu() {
        refreshSettingsModel()
        settingsWindow.show()
    }

    private func wire() {
        // Settings window -> app
        settingsModel.onChange = { [weak self] settings in
            self?.coordinator.apply(settings)
        }
        settingsModel.onRevealPacksFolder = { [weak self] in
            guard let url = self?.coordinator.userPacksDirectory else { return }
            NSWorkspace.shared.open(url)
        }
        settingsModel.onReloadPacks = { [weak self] in
            self?.coordinator.reloadPacks()
            self?.refreshSettingsModel()
        }
        settingsModel.onTestReminder = { [weak self] kind in
            self?.coordinator.triggerReminder(kind)
        }
        settingsModel.onPreviewClip = { [weak self] clip in
            self?.coordinator.previewClip(clip)
        }
        settingsModel.onStartFocus = { [weak self] in
            self?.coordinator.startFocusSession()
        }
        settingsModel.onClearOldDetail = { [weak self] cutoff in
            self?.coordinator.clearOldDetail(before: cutoff)
            self?.refreshSettingsModel()
        }
        settingsModel.onExportHistory = { [weak self] in
            self?.exportHistory()
        }
        settingsModel.onImportPack = { [weak self] url in
            guard let self else { return }
            self.settingsModel.importStatus = "Installing…"
            // Kept on the main thread: the installer draws through
            // NSGraphicsContext, which is not safe to use off it. Measuring a
            // pack takes a moment, so the status line above says what is
            // happening rather than leaving the window looking stuck.
            DispatchQueue.main.async {
                let summary = self.coordinator.installPack(from: url)
                self.settingsModel.importStatus = summary
                self.refreshSettingsModel()
            }
        }
        settingsModel.onBrowseForPack = { [weak self] in
            self?.browseForPack()
        }
        #if AITWIN_DEV
        settingsModel.onPreviewSequence = { [weak self] name in
            self?.coordinator.previewSequence(name)
        }
        settingsModel.onLoadSampleData = { [weak self] in
            self?.coordinator.loadSampleHistory()
            self?.refreshSettingsModel()
        }
        settingsModel.onClearHistory = { [weak self] in
            self?.coordinator.clearHistory()
            self?.refreshSettingsModel()
        }
        #endif

        // App -> settings window, so the menu bar's Pause item and the window's
        // toggle can never disagree.
        coordinator.onSettingsChanged = { [weak self] settings in
            self?.settingsModel.adopt(settings)
            self?.refreshSettingsModel()
        }
        coordinator.onLoginItemFailure = { [weak self] message in
            self?.settingsModel.loginItemWarning = message
        }

        menuBar.onOpenSettings = { [weak self] in
            self?.refreshSettingsModel()
            self?.settingsWindow.show()
        }
        menuBar.onQuit = { [weak self] in
            self?.confirmQuit()
        }
    }

    /// Picks a character pack to install, for anyone who would rather not drag.
    private func browseForPack() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Character"
        panel.message = "Pick a character .zip or a folder of animation folders."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder]

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settingsModel.onImportPack?(url)
    }

    /// Saves the recorded history wherever the user chooses.
    ///
    /// A save panel rather than a fixed location: this is the user's data, and
    /// they should decide where it lands.
    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ActivityLog.exportFilename()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.title = "Export AiTwin History"
        panel.message = "Saved as CSV — opens in Numbers, Excel or any spreadsheet."

        // The app is an accessory, so it is never frontmost; without activating,
        // the panel would open behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try coordinator.exportCSV().write(to: url, atomically: true, encoding: .utf8)

            // Two files, because they are two different shapes of data and one
            // CSV cannot hold both without confusing every spreadsheet. The
            // detail matters most here: it is the only part the monthly
            // clear-out ever removes.
            var saved = [url.lastPathComponent]
            if coordinator.hasDetailToExport {
                let base = url.deletingPathExtension()
                let detailURL = base
                    .appendingPathExtension("detail")
                    .appendingPathExtension(url.pathExtension.isEmpty ? "csv" : url.pathExtension)
                try coordinator.exportEventsCSV()
                    .write(to: detailURL, atomically: true, encoding: .utf8)
                saved.append(detailURL.lastPathComponent)
            }
            settingsModel.importStatus = nil
            settingsModel.exportStatus = saved.count == 1
                ? "Saved \(saved[0])."
                : "Saved \(saved[0]) and \(saved[1]) — the second file holds the hour-by-hour detail."
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func refreshSettingsModel() {
        settingsModel.availablePacks = coordinator.availablePackNames()
        settingsModel.missingClips = coordinator.missingClipNames
        settingsModel.palette = coordinator.companionModel.palette
        settingsModel.availableClips = coordinator.availableClipNames
        settingsModel.activityLog = coordinator.activityLog
        settingsModel.currentStreak = coordinator.currentStreak
        settingsModel.bestStreak = coordinator.bestStreak
    }
}
