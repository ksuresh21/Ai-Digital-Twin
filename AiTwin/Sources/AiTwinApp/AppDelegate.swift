import AppKit
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

    private func refreshSettingsModel() {
        settingsModel.availablePacks = coordinator.availablePackNames()
        settingsModel.missingClips = coordinator.missingClipNames
        settingsModel.palette = coordinator.companionModel.palette
    }
}
