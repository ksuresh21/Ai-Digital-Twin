#if AITWIN_DEV
import SwiftUI
import AiTwinCore

/// Developer tools: trigger every behaviour the app has, and load sample data.
///
/// **Compiled only into debug builds.** The whole file sits behind `AITWIN_DEV`,
/// which `Package.swift` sets with `.when(configuration: .debug)`, so a release
/// build does not contain this code at all.
///
/// Organised by *what triggers it in real use* rather than by animation, so the
/// list doubles as an inventory: everything the character can do is here, and
/// anything missing from this list is not implemented.
struct DeveloperSettingsTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Label("Debug build only — not present in release builds", systemImage: "hammer.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("Reminders") {
                Text("Fires the real reminder, exactly as the timer would.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.displayName) {
                        Button("Trigger") { model.onTestReminder?(kind) }
                    }
                }
            }

            Section("Behaviours") {
                Text("Plays a whole routine — several poses in order — so you can check it reads correctly end to end.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ClipSequence.all, id: \.name) { routine in
                    LabeledContent {
                        Button("Play") { model.onPreviewSequence?(routine.name) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.title(for: routine.name))
                            Text(routine.clips.joined(separator: " → "))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Focus session") {
                Text("A session sits her down, suppresses every reminder, then ends with her standing up and cheering.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Start a Session Now") { model.onStartFocus?() }
            }

            Section("Single poses") {
                Text("One animation on its own. Useful for checking new artwork; use Behaviours to check the transitions.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                    ForEach(model.availableClips, id: \.self) { clip in
                        Button(clip) { model.onPreviewClip?(clip) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if model.availableClips.isEmpty {
                    Text("No clips loaded — pick a character first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.missingClips.isEmpty {
                    Text("This character has no art for: \(model.missingClips.joined(separator: ", ")). Those fall back to idle.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Sample data") {
                Text("30 days of plausible history — including missed days, so streaks and the taken/snoozed/missed chart have something real to show.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Load Sample History") { model.onLoadSampleData?() }
                    Button("Clear History") { model.onClearHistory?() }
                }
            }

            Section("Test mode") {
                Toggle("Allow 10s / 30s / 1m intervals", isOn: $model.settings.testModeEnabled)
                Text("Adds short intervals to the pickers. The reminder logic is unchanged — only the numbers differ, which is the only way testing it proves anything.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// What actually causes each routine in normal use.
    static func title(for routine: String) -> String {
        switch routine {
        case "greeting":      return "Greeting — launch, or waking the Mac"
        case "waterLogged":   return "Water logged — after you tap Done"
        case "stretch":       return "Stretch reminder"
        case "focusFinished": return "Focus session finished"
        case "milestone":     return "Streak milestone (3/7/14/30/100 days)"
        case "sleep":         return "Late night — yawn, then doze off"
        case "concern":       return "Concerned — skipped reminders, or a long stretch"
        case "peek":          return "Idle chatter — peeks in from the edge"
        default:              return routine
        }
    }
}
#endif
