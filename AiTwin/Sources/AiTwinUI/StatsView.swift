import SwiftUI
import AiTwinCore

/// Streaks and the last seven days.
///
/// Deliberately small: a bar chart, two numbers, and an honest acceptance rate.
/// A wellbeing app that turns into a dashboard stops being a companion.
public struct StatsView: View {
    let log: ActivityLog
    let streak: Int
    let best: Int
    let intake: WaterIntake

    /// Called when the user asks for the history as a file.
    let onExport: (() -> Void)?

    public init(log: ActivityLog, streak: Int, best: Int, intake: WaterIntake,
                onExport: (() -> Void)? = nil) {
        self.log = log
        self.streak = streak
        self.best = best
        self.intake = intake
        self.onExport = onExport
    }

    private var week: [DailyRecord] { log.recentDays(7, endingAt: Date()) }

    public var body: some View {
        Form {
            Section("Streak") {
                HStack(spacing: 24) {
                    StatTile(value: "\(streak)", label: streak == 1 ? "day" : "days", accent: true)
                    StatTile(value: "\(best)", label: "best")
                    StatTile(
                        value: WaterIntake.format(
                            millilitres: intake.millilitres(forGlasses: log.totalGlasses(inLast: 7, endingAt: Date()))
                        ),
                        label: "this week"
                    )
                }
                .frame(maxWidth: .infinity)

                if streak == 0 {
                    Text("Hit your daily water goal to start a streak.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let next = ActivityLog.milestones.first(where: { $0 > streak }) {
                    Text("\(next - streak) more day\(next - streak == 1 ? "" : "s") to the \(next)-day milestone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Last 7 days") {
                WeekChart(week: week, intake: intake)
                    .frame(height: 118)
            }

            Section("Eye breaks") {
                BreakBreakdown(week: week)
            }

            Section("Your data") {
                Text("Everything above is stored on this Mac only. Export it as a CSV to open in Numbers, Excel or anything else.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export History as CSV…") { onExport?() }
                    Text("\(log.days.count) day\(log.days.count == 1 ? "" : "s") recorded")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if log.days.isEmpty {
                    Text("Nothing recorded yet — the chart fills in as you use the app.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Focus") {
                let minutes = log.totalFocusMinutes(inLast: 7, endingAt: Date())
                let sessions = week.reduce(0) { $0 + $1.focusSessionsCompleted }
                if sessions == 0 {
                    Text("No focus sessions yet this week. Start one from the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(sessions) session\(sessions == 1 ? "" : "s"), \(Int(minutes)) minutes this week.")
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? Color.accentColor : Color.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Glasses per day, with the goal marked.
struct WeekChart: View {
    let week: [DailyRecord]
    let intake: WaterIntake

    /// Charted in millilitres, which is what the goal is expressed in.
    private var values: [Int] { week.map { intake.millilitres(forGlasses: $0.glasses) } }
    private var scale: Int { max(intake.dailyGoal, values.max() ?? 0, 1) }

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(8.0, geo.size.width / Double(max(week.count, 1)) - 10)
            let chartHeight = geo.size.height - 20
            // The goal line only means something once a goal is set.
            let goalY = chartHeight * (1 - Double(intake.dailyGoal) / Double(scale))

            ZStack(alignment: .topLeading) {
                if true {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: goalY))
                        path.addLine(to: CGPoint(x: geo.size.width, y: goalY))
                    }
                    .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(week.enumerated()), id: \.element.dayStart) { index, day in
                        let millilitres = intake.millilitres(forGlasses: day.glasses)
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(millilitres >= intake.dailyGoal ? Color.accentColor : Color.secondary.opacity(0.45))
                                .frame(
                                    width: barWidth,
                                    height: max(2, chartHeight * Double(millilitres) / Double(scale))
                                )
                            Text(Self.weekdayLetter(day.dayStart))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: geo.size.height, alignment: .bottom)
                    }
                }
            }
        }
    }

    static func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

/// Accepted vs snoozed vs ignored — the number that would actually change behaviour.
struct BreakBreakdown: View {
    let week: [DailyRecord]

    private var accepted: Int { week.reduce(0) { $0 + $1.eyeBreaksAccepted } }
    private var snoozed: Int { week.reduce(0) { $0 + $1.eyeBreaksSnoozed } }
    private var ignored: Int { week.reduce(0) { $0 + $1.eyeBreaksIgnored } }
    private var total: Int { accepted + snoozed + ignored }

    var body: some View {
        if total == 0 {
            Text("No eye breaks offered yet this week.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(accepted, geo.size.width, .green)
                        segment(snoozed, geo.size.width, .orange)
                        segment(ignored, geo.size.width, .secondary.opacity(0.5))
                    }
                }
                .frame(height: 10)

                HStack(spacing: 14) {
                    legend("Taken", accepted, .green)
                    legend("Snoozed", snoozed, .orange)
                    legend("Missed", ignored, .secondary)
                }
                .font(.caption)

                Text("You took \(Int((Double(accepted) / Double(total) * 100).rounded()))% of the breaks offered.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func segment(_ count: Int, _ width: Double, _ colour: Color) -> some View {
        if count > 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(colour)
                .frame(width: max(2, width * Double(count) / Double(total)))
        }
    }

    private func legend(_ title: String, _ count: Int, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text("\(title) \(count)").foregroundStyle(.secondary)
        }
    }
}
