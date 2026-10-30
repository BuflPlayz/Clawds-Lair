import SwiftUI

/// A contribution-style grid of days, like the activity calendar in Claude: one column per
/// week, newest on the right, shaded by how many tokens were used that day.
struct ActivityCalendar: View {
    /// Local day ("yyyy-MM-dd") → tokens.
    let daily: [String: Int]
    let color: Color
    @Binding var hovered: Date?

    @State private var width: CGFloat = 640
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 26
    private let monthRow: CGFloat = 15

    /// A full year when it fits; on narrow windows, fewer weeks rather than tiny squares.
    private var weeks: Int {
        let available = width - labelWidth + gap
        return max(8, min(53, Int(available / (9 + gap))))
    }

    /// Squares grow to fill the width, up to a size that still reads as a calendar.
    private var cell: CGFloat {
        let available = width - labelWidth - gap * CGFloat(weeks - 1)
        return min(16, max(9, available / CGFloat(weeks)))
    }

    var body: some View {
        grid(weeks: weeks)
            .frame(height: monthRow + 7 * cell + 6 * gap, alignment: .top)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func grid(weeks: Int) -> some View {
        let days = CalendarDays(weeks: weeks)
        let levels = Levels(daily.values.filter { $0 > 0 })
        return ZStack(alignment: .topLeading) {
            ForEach(days.monthLabels, id: \.column) { label in
                Text(label.title)
                    .font(.sans(10))
                    .foregroundStyle(Color.textTertiary)
                    .offset(x: labelWidth + CGFloat(label.column) * (cell + gap))
            }
            ForEach([1, 3, 5], id: \.self) { row in
                Text(days.weekdaySymbol(row))
                    .font(.sans(9))
                    .foregroundStyle(Color.textTertiary)
                    .frame(height: cell)
                    .offset(y: monthRow + CGFloat(row) * (cell + gap))
            }
            squares(days: days, levels: levels)
                .offset(x: labelWidth, y: monthRow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// All the day squares drawn in one canvas with a single hover region; hundreds of separate
    /// views each tracking hover made scrolling past the calendar stutter.
    private func squares(days: CalendarDays, levels: Levels) -> some View {
        let step = cell + gap
        let radius = cell * 0.27
        // Level per square, or nil for days after today.
        let grid: [[Int?]] = (0..<weeks).map { column in
            (0..<7).map { row in
                days.date(column: column, row: row).map { levels.level(daily[DayKey.string($0)] ?? 0) }
            }
        }
        let hoveredCell = hovered.flatMap { days.cell(for: $0) }
        let fills = (0...4).map(fill)
        return Canvas { context, _ in
            for (column, levelsInWeek) in grid.enumerated() {
                for (row, level) in levelsInWeek.enumerated() {
                    guard let level else { continue }
                    let rect = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: cell, height: cell)
                    let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                    context.fill(shape, with: .color(fills[level]))
                    if hoveredCell?.column == column && hoveredCell?.row == row {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius,
                                            style: .continuous),
                                       with: .color(.primary.opacity(0.6)), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: CGFloat(weeks) * step - gap, height: 7 * step - gap)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let column = Int(point.x / step), row = Int(point.y / step)
                let date = (0..<weeks).contains(column) && (0..<7).contains(row)
                    ? days.date(column: column, row: row) : nil
                if date != hovered { hovered = date }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
    }

    private func fill(_ level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.07) : color.opacity([0.3, 0.52, 0.76, 1][level - 1])
    }
}

/// The legend under the grid.
struct ActivityLegend: View {
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("Less").padding(.trailing, 3)
            RoundedRectangle(cornerRadius: 2.5).fill(Color.primary.opacity(0.07)).frame(width: 10, height: 10)
            ForEach([0.3, 0.52, 0.76, 1], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 2.5).fill(color.opacity(opacity)).frame(width: 10, height: 10)
            }
            Text("More").padding(.leading, 3)
        }
        .font(.sans(10))
        .foregroundStyle(Color.textTertiary)
    }
}

/// Day keys in the same format StatsEngine uses, without touching its lock.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

/// Summary numbers for the visible range.
struct ActivitySummary {
    var activeDays = 0
    var totalDays = 0
    var streak = 0

    init(daily: [String: Int], days: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var counting = true
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let used = (daily[DayKey.string(date)] ?? 0) > 0
            if used { activeDays += 1 }
            // A streak still counts if today simply hasn't been used yet.
            if counting {
                if used { streak += 1 } else if offset > 0 { counting = false }
            }
        }
        totalDays = days
    }
}

// MARK: - Layout helpers

private struct CalendarDays {
    let weeks: Int
    private let cal = Calendar.current
    private let today: Date
    /// First day of the week that holds today, shown in the last column.
    private let lastWeekStart: Date

    init(weeks: Int) {
        self.weeks = weeks
        today = cal.startOfDay(for: .now)
        let row = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        lastWeekStart = cal.date(byAdding: .day, value: -row, to: today) ?? today
    }

    func date(column: Int, row: Int) -> Date? {
        let offset = -(weeks - 1 - column) * 7 + row
        guard let date = cal.date(byAdding: .day, value: offset, to: lastWeekStart), date <= today else { return nil }
        return date
    }

    /// Where a date sits in the grid, if it's on screen.
    func cell(for date: Date) -> (column: Int, row: Int)? {
        let day = cal.startOfDay(for: date)
        guard let offset = cal.dateComponents([.day], from: lastWeekStart, to: day).day else { return nil }
        let column = weeks - 1 + Int((Double(offset) / 7).rounded(.down))
        let row = offset - (column - (weeks - 1)) * 7
        guard (0..<weeks).contains(column), (0..<7).contains(row), day <= today else { return nil }
        return (column, row)
    }

    func weekdaySymbol(_ row: Int) -> String {
        let symbols = cal.shortWeekdaySymbols
        return symbols[(cal.firstWeekday - 1 + row) % 7]
    }

    struct MonthLabel {
        let column: Int
        let title: String
    }

    /// A label over the first column of each month, skipping any that would crowd the previous one.
    var monthLabels: [MonthLabel] {
        var out: [MonthLabel] = []
        var lastMonth: Int?
        for column in 0..<weeks {
            guard let start = date(column: column, row: 0) else { continue }
            let month = cal.component(.month, from: start)
            defer { lastMonth = month }
            guard month != lastMonth else { continue }
            if let previous = out.last, column - previous.column < 3 { continue }
            if lastMonth == nil, weeks - column > 2, cal.component(.day, from: start) > 14 { continue }
            out.append(MonthLabel(column: column, title: cal.shortMonthSymbols[month - 1]))
        }
        return out
    }
}

/// Splits non-zero days into four shades by quartile, so one huge day doesn't wash out the rest.
private struct Levels {
    private let cuts: [Int]

    init(_ values: [Int]) {
        let sorted = values.sorted()
        cuts = sorted.isEmpty ? [] : [0.25, 0.5, 0.75].map { sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
    }

    func level(_ tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        guard !cuts.isEmpty else { return 4 }
        return 1 + cuts.filter { tokens > $0 }.count
    }
}
