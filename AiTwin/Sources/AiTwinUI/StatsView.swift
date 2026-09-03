import SwiftUI
import AiTwinCore

/// What you actually did — today, or across the last week.
///
/// The previous version of this screen charted whatever the data happened to
/// contain: a bar per day of raw glass counts, and an eye-break "acceptance
/// rate" as a percentage. Neither answered the question anyone actually has,
/// which is *what did I do today*. So this asks that instead, in plain
/// quantities, with the week behind a picker rather than mixed into the same
/// view.
public struct StatsView: View {
    let log: ActivityLog
    let streak: Int
    let best: Int
    let intake: WaterIntake

    /// Called when the user asks for the history as a file.
    let onExport: (() -> Void)?
    /// Called when the user agrees to clear detail older than the given date.
    let onClearOldDetail: ((Date) -> Void)?
    /// What the last export wrote, if anything.
    let exportStatus: String?

    @State private var range: Range = .today
    /// Which activity the hour-by-hour line is showing. Nil is everything.
    @State private var dayFilter: TimedEvent.Activity?

    public init(log: ActivityLog, streak: Int, best: Int, intake: WaterIntake,
                exportStatus: String? = nil,
                onExport: (() -> Void)? = nil,
                onClearOldDetail: ((Date) -> Void)? = nil) {
        self.exportStatus = exportStatus
        self.log = log
        self.streak = streak
        self.best = best
        self.intake = intake
        self.onExport = onExport
        self.onClearOldDetail = onClearOldDetail
    }

    enum Range: String, CaseIterable, Identifiable {
        case today, week
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return "Today"
            case .week:  return "Last 7 days"
            }
        }
    }

    private var now: Date { Date() }
    private var today: DaySummary {
        DaySummary.from(log.record(on: now) ?? DailyRecord(dayStart: now), intake: intake)
    }
    private var week: [DaySummary] {
        log.recentDays(7, endingAt: now).map { DaySummary.from($0, intake: intake) }
    }

    public var body: some View {
        Form {
            if case .offerClearing(let count, let cutoff) =
                DataRetention.notice(for: log, at: now) {
                Section {
                    OldDetailBanner(
                        message: DataRetention.explanation(events: count, upTo: cutoff),
                        onExport: onExport,
                        onClear: onClearOldDetail == nil ? nil : { onClearOldDetail?(cutoff) }
                    )
                }
            }

            Section {
                Picker("Showing", selection: $range) {
                    ForEach(Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch range {
            case .today: todaySections
            case .week:  weekSections
            }

            Section("Your data") {
                Text("Everything here is stored on this Mac only, and never leaves it. "
                     + "Daily totals are kept for good; export them as a CSV to open in "
                     + "Numbers or Excel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export as CSV…") { onExport?() }
                    Spacer()
                    Text(log.days.isEmpty
                         ? "Nothing recorded yet"
                         : "\(log.days.count) day\(log.days.count == 1 ? "" : "s") recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let exportStatus {
                    Text(exportStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Today

    @ViewBuilder
    private var todaySections: some View {
        Section("Today") {
            WaterRow(day: today, intake: intake)
            ActivityRow(label: "Eye breaks taken", value: "\(today.eyeBreaksTaken)",
                        detail: today.eyeBreaksSnoozed + today.eyeBreaksMissed > 0
                            ? "\(today.eyeBreaksSnoozed) snoozed · \(today.eyeBreaksMissed) missed"
                            : nil)
            ActivityRow(label: "Stretches done", value: "\(today.stretchesTaken)",
                        detail: today.stretchesSnoozed + today.stretchesMissed > 0
                            ? "\(today.stretchesSnoozed) snoozed · \(today.stretchesMissed) missed"
                            : nil)
            ActivityRow(label: "Focus sessions", value: "\(today.focusSessions)",
                        detail: today.focusMinutes > 0 ? "\(Int(today.focusMinutes)) minutes" : nil)
            ActivityRow(label: "Skipped altogether", value: "\(today.skipped)",
                        detail: "snoozed or missed, both kinds")
        }

        Section("Through the day") {
            let events = log.events(on: now)
            if events.isEmpty {
                Text(log.events.isEmpty
                     ? "The hour-by-hour view starts recording from today onwards — it "
                       + "cannot show days that have already passed."
                     : "Nothing logged yet today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // One line at a time rather than four overlaid. Across 24 hours
                // with a handful of events in each, four lines are mostly flat
                // and mostly on top of each other -- readable as a legend, not
                // as a chart. The filter has been in `HourlyActivity.buckets`
                // since it was written; only the UI for it was missing, so
                // every activity was counted into one anonymous total.
                Picker("Showing", selection: $dayFilter) {
                    Text("Everything").tag(TimedEvent.Activity?.none)
                    ForEach(TimedEvent.Activity.allCases, id: \.self) { activity in
                        Text(activity.displayName).tag(TimedEvent.Activity?.some(activity))
                    }
                }
                .pickerStyle(.menu)

                let buckets = HourlyActivity.buckets(from: events, activity: dayFilter)
                HourLine(buckets: buckets)
                    .frame(height: 110)

                if let busiest = HourlyActivity.busiestHour(buckets) {
                    Text("Busiest around \(Self.hourLabel(busiest.hour)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let filter = dayFilter {
                    // An empty chart has to say *why* it is empty, or a filter
                    // with nothing in it looks like the recording is broken.
                    Text("No \(filter.displayName.lowercased()) logged today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        streakSection
    }

    // MARK: Last 7 days

    @ViewBuilder
    private var weekSections: some View {
        Section("Water") {
            DayBars(values: week.map { Double($0.millilitres) },
                    days: week.map(\.dayStart),
                    goal: week.last.map { Double($0.goalMillilitres) },
                    format: { WaterIntake.format(millilitres: Int($0)) })
        }
        Section("Eye breaks taken") {
            DayBars(values: week.map { Double($0.eyeBreaksTaken) },
                    days: week.map(\.dayStart), goal: nil,
                    format: { "\(Int($0))" })
        }
        Section("Stretches done") {
            DayBars(values: week.map { Double($0.stretchesTaken) },
                    days: week.map(\.dayStart), goal: nil,
                    format: { "\(Int($0))" })
        }
        Section("Focus minutes") {
            DayBars(values: week.map(\.focusMinutes),
                    days: week.map(\.dayStart), goal: nil,
                    format: { "\(Int($0)) min" })
        }
        Section("This week") {
            let skipped = week.reduce(0) { $0 + $1.skipped }
            ActivityRow(label: "Skipped altogether", value: "\(skipped)",
                        detail: "snoozed or missed, across the week")
        }

        streakSection
    }

    // MARK: Streak

    @ViewBuilder
    private var streakSection: some View {
        Section("Streak") {
            // The old version showed two bare numbers labelled "Current" and
            // "Best", which never said what a streak was counting.
            Text(streak == 0
                 ? "A streak is the number of days in a row you reach your daily water goal of \(WaterIntake.format(millilitres: intake.dailyGoal)). Hit it today to start one."
                 : "\(streak) day\(streak == 1 ? "" : "s") in a row reaching your \(WaterIntake.format(millilitres: intake.dailyGoal)) water goal.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if best > 0 {
                LabeledContent("Longest so far", value: "\(best) day\(best == 1 ? "" : "s")")
            }
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Rows

/// Water gets its own row: it is the one activity with a daily target, so a
/// bare count would lose the only thing that makes it meaningful.
struct WaterRow: View {
    let day: DaySummary
    let intake: WaterIntake

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Water")
                Spacer()
                Text("\(WaterIntake.format(millilitres: day.millilitres)) of \(WaterIntake.format(millilitres: day.goalMillilitres))")
                    .monospacedDigit()
                    .foregroundStyle(day.metWaterGoal ? Color.green : .primary)
            }
            ProgressView(value: day.waterProgress)
                .tint(day.metWaterGoal ? .green : .accentColor)
        }
    }
}

struct ActivityRow: View {
    let label: String
    let value: String
    let detail: String?

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).monospacedDigit()
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(label)
        }
    }
}

// MARK: - Charts

/// Today, hour by hour. A line rather than bars: hours are continuous, so the
/// shape of the day is the point.
struct HourLine: View {
    let buckets: [HourlyActivity.Bucket]

    private var peak: Double { max(1, Double(buckets.map(\.count).max() ?? 1)) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height - 16
            let step = buckets.count > 1 ? width / Double(buckets.count - 1) : width
            // Precomputed: a result builder cannot contain a function
            // declaration, and inlining the maths twice would drift.
            let points = buckets.indices.map { index in
                CGPoint(x: Double(index) * step,
                        y: height - (Double(buckets[index].count) / peak) * height)
            }

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.28), .clear],
                                     startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // Six-hourly ticks: a label per hour is unreadable at this width.
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(StatsView.hourLabel(hour))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: width / 4, alignment: .leading)
                    }
                }
                .offset(y: 8)
            }
        }
    }
}

/// One metric across seven days. Bars, because days are discrete buckets and a
/// line between them would imply values that do not exist.
struct DayBars: View {
    let values: [Double]
    let days: [Date]
    let goal: Double?
    let format: (Double) -> String

    private var peak: Double { max(goal ?? 0, values.max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColour(value))
                            .frame(height: max(2, (value / peak) * 56))
                        Text(Self.weekdayLetter(days[index]))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 74)

            let total = values.reduce(0, +)
            Text(values.allSatisfy { $0 == 0 }
                 ? "Nothing recorded this week."
                 : "\(format(total)) over 7 days · best day \(format(values.max() ?? 0))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func barColour(_ value: Double) -> Color {
        guard let goal, goal > 0 else {
            return value > 0 ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.18)
        }
        if value <= 0 { return Color.secondary.opacity(0.18) }
        return value >= goal ? .green : Color.accentColor.opacity(0.85)
    }

    static func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Retention banner

/// Offers to clear out old hour-by-hour detail. Never acts on its own.
struct OldDetailBanner: View {
    let message: String
    let onExport: (() -> Void)?
    let onClear: (() -> Void)?

    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Export as CSV…") { onExport?() }
                if onClear != nil {
                    Button("Clear Old Detail…") { confirming = true }
                }
            }
        }
        .confirmationDialog("Clear the old hour-by-hour detail?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Clear Old Detail", role: .destructive) { onClear?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your daily totals and streaks are not affected — only the detail "
                 + "behind the by-hour view is removed. This cannot be undone.")
        }
    }
}
