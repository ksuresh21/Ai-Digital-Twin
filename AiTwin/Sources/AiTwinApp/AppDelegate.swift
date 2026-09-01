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

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
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
        menuBar.onQuit = {
            NSApp.terminate(nil)
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
