import SwiftUI
import AiTwinCore

/// The one place every customisation lives, as the spec asks.
///
/// Three tabs so no single pane becomes a wall of controls: what reminds you,
/// who does the reminding, and how the app behaves.
public struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            RemindersSettingsTab(model: model)
                .tabItem { Label("Reminders", systemImage: "bell") }
            CharacterSettingsTab(model: model)
                .tabItem { Label("Character", systemImage: "figure.wave") }
            GeneralSettingsTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 470)
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

                Stepper(
                    "Daily goal: \(model.settings.dailyWaterGoal) glasses",
                    value: $model.settings.dailyWaterGoal,
                    in: 1...20
                )
            }

            Section("Eye breaks") {
                Toggle("Remind me to rest my eyes", isOn: $model.settings.eyeBreakEnabled)
                IntervalPicker(
                    title: "Every",
                    value: $model.settings.eyeBreakInterval,
                    choices: model.choices(including: model.settings.eyeBreakInterval)
                )
                .disabled(!model.settings.eyeBreakEnabled)
            }

            Section("Eye break") {
                Toggle("Dim the screen during the break", isOn: $model.settings.dimsScreenOnBreak)
                Text("Tapping \"Looked away\" starts a timer and dims your screen, so you actually rest your eyes instead of dismissing a message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Break lasts", selection: $model.settings.eyeBreakDuration) {
                    ForEach(BreakCountdown.durationChoices, id: \.self) { seconds in
                        Text(BreakCountdown.durationName(seconds)).tag(seconds)
                    }
                }
                .disabled(!model.settings.dimsScreenOnBreak)

                VStack(alignment: .leading) {
                    Slider(value: $model.settings.dimOpacity, in: 0.3...0.92) {
                        Text("Dim level")
                    }
                    Text("\(Int(model.settings.dimOpacity * 100))% — the screen only dims, it never blocks clicks or typing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.settings.dimsScreenOnBreak)
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
                Toggle("Wearing glasses", isOn: $model.settings.wearsGlasses)

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

            Section("Your own character") {
                Text("Drop a folder of pixel-art frames into the Characters folder, then reload.")
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

            Section("Developer") {
                Toggle("Test mode (allow 10s / 30s / 1m intervals)", isOn: $model.settings.testModeEnabled)
                Text("Adds very short intervals to the pickers above. The reminder logic itself is unchanged — only the numbers differ.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Test Water Reminder") { model.onTestReminder?(.water) }
                    Button("Test Eye Break") { model.onTestReminder?(.eyeBreak) }
                }
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
