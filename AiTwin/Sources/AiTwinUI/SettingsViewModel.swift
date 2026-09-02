import SwiftUI
import AiTwinCore
import AiTwinPlatform

/// Backs the Settings window.
///
/// Holds one `AiTwinSettings` and publishes every change straight through to the
/// app, so a slider moves and the running timer changes immediately -- there is
/// no Apply button and no way for the window and the engine to disagree.
@MainActor
public final class SettingsViewModel: ObservableObject {

    @Published public var settings: AiTwinSettings {
        didSet {
            guard settings != oldValue else { return }
            onChange?(settings)
        }
    }

    /// Names of every installed character pack, for the picker.
    @Published public var availablePacks: [String] = []
    /// Clips the selected pack is missing, shown as a gentle warning.
    @Published public var missingClips: [String] = []
    /// Set when macOS refuses a login-item change, which usually means the user
    /// has to approve it in System Settings.
    @Published public var loginItemWarning: String?
    @Published public var isDropTargeted: Bool = false
    /// What happened to the last import, shown under the drop zone.
    @Published public var importStatus: String?
    /// The current character's colours, so the style previews look like the
    /// real thing rather than a generic swatch.
    @Published public var palette: CharacterPalette = .fallback
    /// Clips the current pack provides, for the mood test buttons.
    @Published public var availableClips: [String] = []
    @Published public var activityLog: ActivityLog = ActivityLog()
    @Published public var currentStreak: Int = 0
    @Published public var bestStreak: Int = 0

    public var onChange: ((AiTwinSettings) -> Void)?
    public var onRevealPacksFolder: (() -> Void)?
    public var onReloadPacks: (() -> Void)?
    public var onTestReminder: ((ReminderKind) -> Void)?
    /// Plays one clip on demand so new artwork can be checked.
    public var onPreviewClip: ((String) -> Void)?
    public var onStartFocus: (() -> Void)?
    /// Saves the recorded history to a file the user picks.
    /// What the last export wrote, shown under the export button.
    @Published public var exportStatus: String?
    public var onExportHistory: (() -> Void)?
    /// Clears timestamped detail older than the given date. Daily totals stay.
    public var onClearOldDetail: ((Date) -> Void)?
    /// Installs a pack from a dropped zip or folder.
    public var onImportPack: ((URL) -> Void)?
    public var onBrowseForPack: (() -> Void)?
    /// Plays a whole routine, for checking a behaviour end to end.
    public var onPreviewSequence: ((String) -> Void)?
    public var onLoadSampleData: (() -> Void)?
    public var onClearHistory: (() -> Void)?

    public init(settings: AiTwinSettings) {
        self.settings = settings
    }

    /// Replaces settings without echoing a change back to the app. Used when
    /// something else (the menu bar's Pause item) changes them.
    public func adopt(_ newSettings: AiTwinSettings) {
        guard newSettings != settings else { return }
        let handler = onChange
        onChange = nil
        settings = newSettings
        onChange = handler
    }

    /// Interval choices, widened with the very short ones when Test Mode is on.
    public var intervalChoices: [IntervalPreset] {
        settings.testModeEnabled
            ? IntervalPreset.testing + IntervalPreset.standard
            : IntervalPreset.standard
    }

    /// Presents an interval that is not one of the presets as a custom entry, so
    /// the picker always has a selected row.
    public func choices(including value: TimeInterval) -> [IntervalPreset] {
        let choices = intervalChoices
        return choices.contains(where: { $0.seconds == value })
            ? choices
            : ([.custom(value)] + choices)
    }
}
