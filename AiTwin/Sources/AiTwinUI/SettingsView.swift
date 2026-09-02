import SwiftUI
import AiTwinCore

/// The one place every customisation lives, as the spec asks.
///
/// Three tabs so no single pane becomes a wall of controls: what reminds you,
/// who does the reminding, and how the app behaves.
/// Settings, laid out as a sidebar rather than a row of tabs.
///
/// A tab bar was the first attempt and it was the wrong control: with six
/// sections the tabs were tiny, unlabelled at a glance, and gave no sense of
/// where you were. A sidebar is what macOS itself moved to for System Settings,
/// and for the same reasons -- every section is visible at once, named, and
/// selectable in one click instead of two.
public struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var section: Section = .general

    public init(model: SettingsViewModel) {
        self.model = model
    }

    enum Section: String, CaseIterable, Identifiable {
        case general, reminders, focus, character, stats
        #if AITWIN_DEV
        case developer
        #endif

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reminders: return "Reminders"
            case .focus:     return "Focus"
            case .character: return "Character"
            case .stats:     return "Progress"
            case .general:   return "General"
            #if AITWIN_DEV
            case .developer: return "Developer"
            #endif
            }
        }

        var icon: String {
            switch self {
            case .reminders: return "bell.fill"
            case .focus:     return "timer"
            case .character: return "figure.wave"
            case .stats:     return "chart.bar.fill"
            case .general:   return "gearshape.fill"
            #if AITWIN_DEV
            case .developer: return "hammer.fill"
            #endif
            }
        }

        var subtitle: String {
            switch self {
            case .reminders: return "Water, eyes, posture"
            case .focus:     return "Sessions and chatter"
            case .character: return "Look and message style"
            case .stats:     return "Streaks and history"
            case .general:   return "Name, startup, quiet hours"
            #if AITWIN_DEV
            case .developer: return "Previews and sample data"
            #endif
            }
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 720, height: 540)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A single identity line, so the window says whose settings these are.
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AiTwin").font(.system(size: 13, weight: .semibold))
                    Text(model.settings.characterPackName)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ForEach(Section.allCases) { item in
                SidebarRow(section: item, isSelected: section == item)
                    .onTapGesture { section = item }
            }

            Spacer()

            if model.currentStreak > 0 {
                HStack(spacing: 6) {
                    Text("🔥").font(.system(size: 13))
                    Text("\(model.currentStreak) day streak")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 208)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.system(size: 17, weight: .semibold))
                Text(section.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            switch section {
            case .reminders: RemindersSettingsTab(model: model)
            case .focus:     FocusSettingsTab(model: model)
            case .character: CharacterSettingsTab(model: model)
            case .general:   GeneralSettingsTab(model: model)
            #if AITWIN_DEV
            case .developer: DeveloperSettingsTab(model: model)
            #endif
            case .stats:
                StatsView(
                    log: model.activityLog,
                    streak: model.currentStreak,
                    best: model.bestStreak,
                    intake: model.settings.water,
                    exportStatus: model.exportStatus,
                    onExport: { model.onExportHistory?() },
                    onClearOldDetail: { cutoff in model.onClearOldDetail?(cutoff) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SidebarRow: View {
    let section: SettingsView.Section
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: section.icon)
                .font(.system(size: 12))
                .frame(width: 18)
                .foregroundStyle(isSelected ? .white : Color.accentColor)
            Text(section.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Reminders

struct RemindersSettingsTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Water") {
                Toggle("Remind me to drink water", isOn: $model.settings.waterEnabled)
                IntervalPicker(
                    title: "Every",
                    value: $model.settings.waterInterval,
                    choices: model.choices(including: model.settings.waterInterval)
                )
                .disabled(!model.settings.waterEnabled)

                Picker("One glass is", selection: $model.settings.water.glassSize) {
                    ForEach(WaterIntake.glassSizeChoices, id: \.self) { size in
                        Text("\(size) ml").tag(size)
                    }
                }
                Picker("Daily goal", selection: $model.settings.water.dailyGoal) {
                    ForEach(WaterIntake.goalChoices, id: \.self) { goal in
                        Text(WaterIntake.format(millilitres: goal)).tag(goal)
                    }
                }
                Text("That's \(model.settings.water.glassesForGoal) glasses a day — about one every \(Int(model.settings.waterInterval / 60)) minutes while you're at the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // One section, not two: the reminder and the break it starts are a
            // single behaviour, and splitting them made the settings read as if
            // there were two separate eye features.
            Section("Eye breaks") {
                Toggle("Remind me to rest my eyes", isOn: $model.settings.eyeBreakEnabled)
                IntervalPicker(
                    title: "Every",
                    value: $model.settings.eyeBreakInterval,
                    choices: model.choices(including: model.settings.eyeBreakInterval)
                )
                .disabled(!model.settings.eyeBreakEnabled)

                Picker("Break lasts", selection: $model.settings.eyeBreakDuration) {
                    ForEach(BreakCountdown.durationChoices, id: \.self) { seconds in
                        Text(BreakCountdown.durationName(seconds)).tag(seconds)
                    }
                }
                .disabled(!model.settings.eyeBreakEnabled)

                Toggle("Dim the screen for the break", isOn: $model.settings.dimsScreenOnBreak)
                    .disabled(!model.settings.eyeBreakEnabled)

                VStack(alignment: .leading) {
                    Slider(value: $model.settings.dimOpacity, in: 0.3...0.92) {
                        Text("How dark")
                    }
                    Text("\(Int(model.settings.dimOpacity * 100))% — dimming only. It never blocks clicks or typing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!model.settings.eyeBreakEnabled || !model.settings.dimsScreenOnBreak)

                Text("Tapping “Looked away” starts the timer and dims your screen, so you actually rest your eyes instead of dismissing a message.")
                    .font(.caption).foregroundStyle(.secondary)
            }


            Section("When you are away") {
                Toggle("Only count time I'm actually using the Mac", isOn: $model.settings.pauseWhenIdle)
                Text("Pauses the countdown after \(Int(model.settings.idleThreshold / 60)) minutes without keyboard or mouse activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Snooze") {
                IntervalPicker(
                    title: "Snooze for",
                    value: $model.settings.snoozeInterval,
                    choices: [.custom(60), .custom(300), .custom(600), .custom(900)]
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Character

struct CharacterSettingsTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Character", selection: $model.settings.characterPackName) {
                    ForEach(model.availablePacks, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                VStack(alignment: .leading) {
                    Slider(value: $model.settings.characterHeight, in: 64...256, step: 8) {
                        Text("Size")
                    }
                    Text("\(Int(model.settings.characterHeight)) points tall")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Message box") {
                BubbleStylePicker(
                    selection: $model.settings.bubbleStyle,
                    palette: model.palette
                )
            }

            Section("Position") {
                Picker("Appears in", selection: $model.settings.corner) {
                    ForEach(ScreenCorner.allCases, id: \.self) { corner in
                        Text(corner.displayName).tag(corner)
                    }
                }
                .pickerStyle(.menu)
            }

            if !model.missingClips.isEmpty {
                Section("Missing animations") {
                    Text("This character has no frames for: \(model.missingClips.joined(separator: ", ")).")
                        .font(.caption)
                    Text("Those animations fall back to Idle. See Docs/PROMPTS.md to generate them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Add your own character") {
                CharacterDropZone(
                    isTargeted: $model.isDropTargeted,
                    status: model.importStatus,
                    onDrop: { url in model.onImportPack?(url) },
                    onBrowse: { model.onBrowseForPack?() }
                )

                Text("A pack is a folder of animation folders — Idle, Walking, Waving and so "
                     + "on — or a .zip of one. Frames are resized and aligned for you, so art "
                     + "drawn at any size works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open Characters Folder…") { model.onRevealPacksFolder?() }
                    Button("Reload Characters") { model.onReloadPacks?() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("About you") {
                TextField("Your name", text: $model.settings.userName, prompt: Text("e.g. Suresh"))
                Text(model.settings.userName.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Leave blank and she'll greet you without a name."
                     : "She'll greet you by name — \"Hey \(model.settings.userName.split(separator: " ").first.map(String.init) ?? model.settings.userName)!\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Start AiTwin at login", isOn: $model.settings.startAtLogin)
                if let warning = model.loginItemWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Say hello when the app opens", isOn: $model.settings.greetOnLaunch)
                Toggle("Say hello when the Mac wakes up", isOn: $model.settings.greetOnWake)
            }

            Section("Quiet hours") {
                Toggle("Stay quiet during set hours", isOn: $model.settings.quietHours.isEnabled)
                TimeOfDayPicker(title: "From", minutes: $model.settings.quietHours.startMinutes)
                    .disabled(!model.settings.quietHours.isEnabled)
                TimeOfDayPicker(title: "Until", minutes: $model.settings.quietHours.endMinutes)
                    .disabled(!model.settings.quietHours.isEnabled)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared controls

/// A picker over `TimeInterval` values presented as friendly names.
struct IntervalPicker: View {
    let title: String
    @Binding var value: TimeInterval
    let choices: [IntervalPreset]

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(choices, id: \.seconds) { choice in
                Text(choice.displayName).tag(choice.seconds)
            }
        }
    }
}

/// Hour and minute steppers over a minutes-since-midnight value.
struct TimeOfDayPicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 64)

            Text(":")

            Picker("", selection: minuteBinding) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 64)
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { minutes / 60 },
            set: { minutes = $0 * 60 + (minutes % 60) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            // Snap to the nearest offered value so an interval stored from an
            // older build cannot leave the picker with no selection.
            get: { [0, 15, 30, 45].contains(minutes % 60) ? minutes % 60 : 0 },
            set: { minutes = (minutes / 60) * 60 + $0 }
        )
    }
}
