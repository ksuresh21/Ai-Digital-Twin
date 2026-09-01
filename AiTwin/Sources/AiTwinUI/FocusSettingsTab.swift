import SwiftUI
import AiTwinCore

/// Focus session settings.
///
/// The important sentence here is the one about reminders being held rather
/// than dropped -- otherwise turning focus on looks like turning the app off.
struct FocusSettingsTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Session") {
                Picker("Focus for", selection: $model.settings.focusSessionLength) {
                    ForEach(FocusController.lengthChoices, id: \.self) { length in
                        Text(FocusController.lengthName(length)).tag(length)
                    }
                }
                Picker("Short break", selection: $model.settings.focusBreakLength) {
                    ForEach(FocusController.breakChoices, id: \.self) { length in
                        Text(FocusController.lengthName(length)).tag(length)
                    }
                }
                Picker("Long break", selection: $model.settings.focusLongBreakLength) {
                    ForEach(FocusController.breakChoices, id: \.self) { length in
                        Text(FocusController.lengthName(length)).tag(length)
                    }
                }
                Stepper(
                    "Long break after \(model.settings.sessionsBeforeLongBreak) sessions",
                    value: $model.settings.sessionsBeforeLongBreak,
                    in: 2...8
                )
            }

            Section("While focusing") {
                Text("She sits down and reads beside you, barely moving — movement in the corner of your eye is exactly what breaks concentration.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("**All reminders are held during a session** and delivered in the break, so nothing is lost.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Start a Session Now") { model.onStartFocus?() }
            }

            Section("How she reacts") {
                Toggle("Notice how the day is going", isOn: $model.settings.moodsEnabled)

                Picker("Check on me after", selection: $model.settings.moodThresholds.workBeforeConcern) {
                    ForEach(MoodMonitor.Thresholds.concernHourChoices, id: \.self) { seconds in
                        Text("\(Int(seconds / 3600)) hours at the screen").tag(seconds)
                    }
                }
                .disabled(!model.settings.moodsEnabled)

                Stepper(
                    "…or after \(model.settings.moodThresholds.skipsBeforeConcern) skipped reminders",
                    value: $model.settings.moodThresholds.skipsBeforeConcern,
                    in: 2...8
                )
                .disabled(!model.settings.moodsEnabled)

                Picker("Wind down from", selection: $model.settings.moodThresholds.nightStartMinutes) {
                    ForEach(MoodMonitor.Thresholds.nightStartChoices, id: \.self) { minutes in
                        Text(QuietHours.format(minuteOfDay: minutes)).tag(minutes)
                    }
                }
                .disabled(!model.settings.moodsEnabled)

                Picker("Remind me to sleep every", selection: $model.settings.moodThresholds.sleepyRepeat) {
                    ForEach(MoodMonitor.Thresholds.repeatChoices, id: \.self) { seconds in
                        Text("\(Int(seconds / 60)) minutes").tag(seconds)
                    }
                }
                .disabled(!model.settings.moodsEnabled)

                Text("After the wind-down time she yawns, then dozes off on your desktop until you shoo her away.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Idle chatter") {
                Picker("She speaks up", selection: $model.settings.chatterFrequency) {
                    ForEach(ChatterScheduler.Frequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                Text(model.settings.chatterFrequency.detail)
                    .font(.caption).foregroundStyle(.secondary)
                Text("Never during a focus session, quiet hours, or while you are away from the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
