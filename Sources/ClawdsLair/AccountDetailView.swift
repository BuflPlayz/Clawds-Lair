import Charts
import SwiftUI

/// A full page of one account's activity, opened from its card.
struct AccountDetailView: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile


    private var stats: ProfileStats { store.stats[profile.id] ?? ProfileStats() }
    private var isActive: Bool { store.activeID == profile.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            insights
            CalendarCard(daily: stats.daily, color: profile.color)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                DailyTokensCard(daily: stats.daily, color: profile.color)
                tokenMix
                models
                usage
            }
        }
    }

    // MARK: Header

    /// Centered like the greeting on the accounts page, straight on the backdrop.
    private var header: some View {
        VStack(spacing: 10) {
            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 88, square: true)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name).font(.serif(32)).lineLimit(1)
                    if isActive {
                        Badge(text: "Open", color: profile.color, live: true)
                    } else if !store.isClaudeRunning && store.residentID == profile.id {
                        Badge(text: "Last used", color: .textSecondary)
                    }
                }
                Text(subtitle).font(.sans(12)).foregroundStyle(Color.textTertiary).lineLimit(1)
            }
            SwitchButton(profile: profile, fullWidth: false)
                .fixedSize()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let last = stats.lastActive {
            parts.append("Last active \(last.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("Not used yet")
        }
        if let id = stats.accountID { parts.append("Account \(id.prefix(8))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Insights

    private var insights: some View {
        let i = ActivityInsights(daily: stats.daily)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            insight(Fmt.tokens(stats.totals.total), "Total tokens", "sparkles")
            insight("\(i.activeDays)", i.activeDays == 1 ? "Active day" : "Active days", "calendar")
            insight(i.currentStreak == 1 ? "1 day" : "\(i.currentStreak) days", "Current streak", "flame")
            insight(i.longestStreak == 1 ? "1 day" : "\(i.longestStreak) days", "Longest streak", "trophy")
            insight(i.averagePerActiveDay > 0 ? Fmt.tokens(i.averagePerActiveDay) : "–", "Per active day", "chart.line.uptrend.xyaxis")
            insight(i.busiest.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? "–",
                    i.busiest.map { "Busiest · \(Fmt.tokens($0.tokens))" } ?? "Busiest day", "bolt")
        }
    }

    private func insight(_ value: String, _ label: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(profile.color)
                .frame(width: 30, height: 30)
                .background(profile.color.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.sans(16, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.sans(11)).foregroundStyle(Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
    }

    // MARK: Token mix

    private var tokenMix: some View {
        let t = stats.totals
        let parts: [(String, Int, Double)] = [
            ("Output", t.output, 1),
            ("Input", t.input, 0.72),
            ("Cache writes", t.cacheWrite, 0.48),
            ("Cache reads", t.cacheRead, 0.26),
        ]
        let total = max(t.total, 1)
        return DetailCard {
            CardHeading("Where the tokens went")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { name, value, opacity in
                        if value > 0 {
                            Rectangle()
                                .fill(profile.color.opacity(opacity))
                                .frame(width: max(3, geo.size.width * CGFloat(value) / CGFloat(total)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .background(Capsule().fill(Color.primary.opacity(0.07)))

            VStack(spacing: 8) {
                ForEach(parts, id: \.0) { name, value, opacity in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(profile.color.opacity(opacity)).frame(width: 10, height: 10)
                        Text(name).font(.sans(12)).foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(Fmt.tokens(value)).font(.sans(12, .medium)).monospacedDigit()
                        Text(percent(value, of: total))
                            .font(.sans(11)).foregroundStyle(Color.textTertiary).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Text("Cache reads are context Claude reuses between turns, so they're usually the biggest share.")
                .font(.sans(11))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Models

    private var models: some View {
        let total = max(stats.totals.total, 1)
        let sorted = stats.byModel.sorted { $0.value.total > $1.value.total }
        return DetailCard {
            HStack {
                CardHeading("Models")
                Spacer()
                Text(sorted.count == 1 ? "1 model" : "\(sorted.count) models")
                    .font(.sans(11)).foregroundStyle(Color.textTertiary)
            }
            if sorted.isEmpty {
                EmptyNote("No Claude Code or Cowork activity yet.")
            } else {
                VStack(spacing: 12) {
                    ForEach(sorted, id: \.key) { model, counts in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(Fmt.model(model)).font(.sans(13, .medium))
                                Spacer()
                                Text(Fmt.tokens(counts.total)).font(.sans(12, .medium)).monospacedDigit()
                                Text(percent(counts.total, of: total))
                                    .font(.sans(11)).foregroundStyle(Color.textTertiary).monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                            Meter(fraction: Double(counts.total) / Double(total), color: profile.color)
                            Text("\(Fmt.tokens(counts.output)) out · \(Fmt.tokens(counts.input)) in · \(Fmt.tokens(counts.messages)) replies")
                                .font(.sans(11)).foregroundStyle(Color.textTertiary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: Usage & storage

    private var usage: some View {
        DetailCard {
            CardHeading("Plan & storage")
            if let plan = stats.planUsage, plan.fiveHour != nil || plan.weekly != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let fh = plan.fiveHour { meter("5-hour limit", fh) }
                    if let wk = plan.weekly { meter("Weekly limit", wk) }
                    Text("Saved by Claude \(plan.at.formatted(.relative(presentation: .named)))")
                        .font(.sans(11)).foregroundStyle(Color.textTertiary)
                        .help(PlanUsage.savedHelp)
                }
                .padding(12)
                .insetFill(cornerRadius: 12)
            }
            VStack(spacing: 0) {
                row("Claude Code sessions", "\(stats.codeSessions)")
                Divider().overlay(Color.hairline)
                row("Cowork sessions", "\(stats.coworkSessions)")
                Divider().overlay(Color.hairline)
                row("Replies", Fmt.tokens(stats.totals.messages))
                Divider().overlay(Color.hairline)
                row("Folder size", Fmt.bytes(stats.folderBytes))
            }
            .padding(.horizontal, 12)
            .insetFill(cornerRadius: 12)
            Button {
                store.reveal(profile)
            } label: {
                Label("Show Folder in Finder", systemImage: "folder").font(.sans(12, .medium))
            }
            .buttonStyle(.glass)
        }
    }

    private func meter(_ label: String, _ percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.sans(12)).foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(percent)%").font(.sans(12, .semibold)).monospacedDigit()
            }
            Meter(fraction: Double(percent) / 100,
                  color: percent >= 90 ? .red : percent >= 70 ? .orange : profile.color)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.sans(12)).foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value).font(.sans(12, .medium)).monospacedDigit()
        }
        .padding(.vertical, 9)
    }

    // MARK: Helpers

    private func percent(_ value: Int, of total: Int) -> String {
        let p = Double(value) / Double(total) * 100
        return p > 0 && p < 1 ? "<1%" : "\(Int(p.rounded()))%"
    }
}

/// Streaks and highlights over an account's whole history.
struct ActivityInsights {
    var activeDays = 0
    var currentStreak = 0
    var longestStreak = 0
    var averagePerActiveDay = 0
    var busiest: (date: Date, tokens: Int)?

    init(daily: [String: Int]) {
        let cal = Calendar.current
        let active = daily.filter { $0.value > 0 }
        activeDays = active.count
        guard !active.isEmpty else { return }
        averagePerActiveDay = active.values.reduce(0, +) / active.count
        if let top = active.max(by: { $0.value < $1.value }), let date = DayKey.date(top.key) {
            busiest = (date, top.value)
        }

        let dates = active.keys.compactMap(DayKey.date).map { cal.startOfDay(for: $0) }.sorted()
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous, cal.dateComponents([.day], from: previous, to: date).day == 1 { run += 1 } else { run = 1 }
            longestStreak = max(longestStreak, run)
            previous = date
        }
        currentStreak = ActivitySummary(daily: daily, days: max(longestStreak + 1, 2)).streak
    }
}

// MARK: - Cards with their own hover state

/// The account's year calendar. Hover lives here so moving over squares, or scrolling them
/// under the pointer, only redraws this card.
private struct CalendarCard: View {
    let daily: [String: Int]
    let color: Color
    @State private var hovered: Date?

    var body: some View {
        DetailCard(spacing: 10) {
            HStack {
                CardHeading("Activity")
                Spacer()
                Text(caption)
                    .font(.sans(12))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }
            ActivityCalendar(daily: daily, color: color, hovered: $hovered)
            HStack {
                Spacer()
                ActivityLegend(color: color)
            }
        }
    }

    private var caption: String {
        if let day = hovered {
            let tokens = daily[DayKey.string(day)] ?? 0
            let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            return tokens > 0 ? "\(date) · \(Fmt.tokens(tokens)) tokens" : "\(date) · No activity"
        }
        return "Active \(ActivitySummary(daily: daily, days: 365).activeDays) of the last 365 days"
    }
}

/// Tokens per day as bars, over 7, 30 or 90 days.
private struct DailyTokensCard: View {
    let daily: [String: Int]
    let color: Color
    @State private var range = 30
    @State private var selectedDay: Date?

    private struct DayValue: Identifiable {
        let date: Date
        let tokens: Int
        var id: Date { date }
    }

    private var days: [DayValue] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<range).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayValue(date: date, tokens: daily[DayKey.string(date)] ?? 0)
        }
    }

    var body: some View {
        let data = days
        let total = data.reduce(0) { $0 + $1.tokens }
        let selected = selectedDay.flatMap { day in data.first { Calendar.current.isDate($0.date, inSameDayAs: day) } }
        DetailCard {
            HStack(spacing: 8) {
                CardHeading("Tokens per day")
                Spacer()
                ForEach([7, 30, 90], id: \.self) { days in
                    GlassChip(selected: range == days, tint: color) {
                        withAnimation(.smooth(duration: 0.3)) { range = days }
                    } label: {
                        Text("\(days)d")
                    }
                }
            }
            .font(.sans(11, .medium))

            Text(selected.map { "\($0.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(Fmt.tokens($0.tokens))" }
                 ?? "\(Fmt.tokens(total)) in the last \(range) days")
                .font(.sans(12))
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()

            Chart(data) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Tokens", day.tokens))
                    .foregroundStyle(color.gradient)
                    .opacity(selected == nil || selected?.id == day.id ? 1 : 0.4)
                    .cornerRadius(range > 30 ? 1.5 : 3)
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel { Text(Fmt.tokens(value.as(Int.self) ?? 0)).font(.sans(10)) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.sans(10))
                }
            }
            .frame(height: 170)
            .overlay {
                if total == 0 { EmptyNote("No activity in the last \(range) days.") }
            }
        }
    }
}

// MARK: - Building blocks

private struct DetailCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .glassCard(cornerRadius: 22)
    }
}

private struct CardHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.sans(13, .semibold)).foregroundStyle(Color.textSecondary)
    }
}

private struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            SparkView(size: 16, color: Color.textTertiary.opacity(0.6), ticklesOnTap: true)
            Text(text).font(.sans(12)).foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}
