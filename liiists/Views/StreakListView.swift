import SwiftUI

/// Streak view: a wrapped, newest-first sequence of circles.
///
/// The row leads (top-left) with a persistent empty **add-button** — always
/// today. Tapping it appends a filled circle just to its right, so the button
/// re-appears on the left and older entries shift right. Each entry is one
/// circle; tapping a filled circle toggles it to an empty placeholder *in
/// place* (it never leaves the row), and tapping that placeholder re-fills it.
/// Long-press any entry to edit its date or remove it outright.
///
/// Time is carried purely by lightweight date labels: "TODAY" over the
/// add-button, then a date roughly every 7 calendar days going back.
struct StreakListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showCadenceSheet = false
    /// Set to a milestone value (7/30/100/365) when the current streak crosses
    /// it, driving a transient celebration overlay.
    @State private var celebration: Int?

    private static let milestones: Set<Int> = [7, 30, 100, 365]
    @State private var editingIndex: Int?
    @State private var pendingDate = Date()
    /// When true, render a Monday-aligned week grid instead of the flow timeline.
    @AppStorage private var weekView: Bool
    /// When true, shrink the continuous-view dots to fit every entry in the
    /// viewport at once (a zoomed-out, bird's-eye glance). Transient — resets to
    /// standard size on re-entry.
    @State private var showAll = false

    private static let circleSize: CGFloat = 30
    private static let circleSpacing: CGFloat = 10
    private static let dateHeaderHeight: CGFloat = 12
    /// Smallest dot the zoomed-out "show all" view will shrink to before it lets
    /// the grid scroll again.
    private static let minCircleSize: CGFloat = 8

    init(list: ItemList) {
        _list = State(initialValue: list)
        _weekView = AppStorage(wrappedValue: false, "streak_week_view_\(list.filename)")
    }

    // MARK: - Cell model

    /// The row is a continuous calendar timeline from the earliest entry up to
    /// today, one circle per day — so gap days show as empty rings. A day with
    /// entries emits one circle per entry (letting a day be logged more than
    /// once); today additionally leads with an always-empty add-button.
    private enum StreakCell: Equatable {
        case add                  // leading today tap-target
        case entry(index: Int)    // a stored entry (filled or unfilled placeholder)
        case gap(day: Date)       // a calendar day with no entry
    }

    private var cells: [StreakCell] {
        Self.buildCells(entries: list.streakEntries, today: Date())
    }

    private static func buildCells(
        entries: [StreakEntry],
        today: Date,
        calendar: Calendar = .current
    ) -> [StreakCell] {
        let todayStart = calendar.startOfDay(for: today)

        var indicesByDay: [Date: [Int]] = [:]
        for (i, entry) in entries.enumerated() {
            indicesByDay[calendar.startOfDay(for: entry.date), default: []].append(i)
        }
        let earliest = entries.map { calendar.startOfDay(for: $0.date) }.min() ?? todayStart
        let start = min(earliest, todayStart)

        var result: [StreakCell] = []
        var day = todayStart
        while day >= start {
            let idxs = indicesByDay[day] ?? []
            if calendar.isDate(day, inSameDayAs: todayStart) {
                result.append(.add)
                for i in idxs { result.append(.entry(index: i)) }
            } else if !idxs.isEmpty {
                for i in idxs { result.append(.entry(index: i)) }
            } else {
                result.append(.gap(day: day))
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return result
    }

    /// The calendar day a cell sits on — used for the 7-day date labels.
    private func cellDay(_ cell: StreakCell) -> Date {
        let cal = Calendar.current
        switch cell {
        case .add:
            return cal.startOfDay(for: Date())
        case let .entry(index):
            guard list.streakEntries.indices.contains(index) else {
                return cal.startOfDay(for: Date())
            }
            return cal.startOfDay(for: list.streakEntries[index].date)
        case let .gap(day):
            return day
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ScrollView {
                    Group {
                        if weekView {
                            weekGrid(circleSize: weekCircleSize(viewport: geo.size))
                        } else {
                            circleGrid(circleSize: continuousCircleSize(viewport: geo.size))
                        }
                    }
                    .padding(.horizontal, Theme.spaceMD)
                    .padding(.top, Theme.spaceLG)
                    .padding(.bottom, Theme.space2XL)
                }
            }
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                }
            }
        }
        .alert("Rename List", isPresented: $showRename) {
            TextField("List name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                store.rename(&list, to: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete List?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.delete(list)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(list.title)\".")
        }
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )) {
            StreakDateEditSheet(
                date: $pendingDate,
                onCommit: {
                    if let idx = editingIndex {
                        list.updateStreakEntry(at: idx, to: pendingDate)
                        Theme.lightHaptic()
                    }
                    editingIndex = nil
                },
                onCancel: {
                    editingIndex = nil
                }
            )
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCadenceSheet) {
            StreakCadenceEditSheet(
                cadence: Binding(
                    get: { list.streakCadence ?? .daily },
                    set: { list.streakCadence = $0 } // onChange(of: list) persists
                ),
                onDone: { showCadenceSheet = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .enableSwipeBack()
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
        .onChange(of: stats.currentStreak) { old, new in
            // Celebrate only when the streak grows into a milestone.
            if new > old, Self.milestones.contains(new) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { celebration = new }
                Theme.mediumHaptic()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    if celebration == new {
                        withAnimation(.easeOut(duration: 0.25)) { celebration = nil }
                    }
                }
            }
        }
        .overlay {
            if let value = celebration {
                celebrationOverlay(value)
            }
        }
    }

    // MARK: - Milestone celebration

    private func celebrationOverlay(_ value: Int) -> some View {
        let isWeek = cadence.period == .week
        return VStack(spacing: Theme.spaceSM) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
            Text("\(value)")
                .font(Theme.headingFont(size: 48, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
            Text(isWeek ? "WEEK STREAK" : "DAY STREAK")
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
        .padding(Theme.space2XL)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.ndSurface.resolve(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 20)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.25)) { celebration = nil }
        }
    }

    // MARK: - Stats

    private var cadence: StreakCadence { list.streakCadence ?? .daily }

    private var stats: StreakStatsResult {
        StreakStats.compute(
            entries: list.streakEntries.filter(\.filled).map(\.date),
            cadence: cadence
        )
    }

    /// Filled completions logged today — the current-period numerator for
    /// day-based cadences.
    private var todayCount: Int {
        let cal = Calendar.current
        return list.streakEntries.filter { $0.filled && cal.isDateInToday($0.date) }.count
    }

    // MARK: - Header

    private var header: some View {
        let s = stats
        let isWeek = cadence.period == .week
        return VStack(alignment: .leading, spacing: Theme.spaceMD) {
            HStack(alignment: .top) {
                Text(list.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
                Spacer()
                overflowMenu
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.spaceLG) {
                statCell(value: s.currentStreak, label: isWeek ? "WEEK STREAK" : "DAY STREAK")
                statCell(value: s.longestStreak, label: "LONGEST")
                statCell(value: s.totalCompletions, label: "LOGGED")
                Spacer()
                if cadence.target > 1 {
                    periodProgress(
                        count: isWeek ? s.thisWeekCount : todayCount,
                        target: cadence.target,
                        label: isWeek ? "THIS WEEK" : "TODAY"
                    )
                }
            }
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.top, Theme.spaceLG)
        .padding(.bottom, Theme.spaceMD)
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(Theme.headingFont(size: 22, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.labelFont(size: 8))
                .tracking(8 * 0.04)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
    }

    /// Compact current-period progress: "2/3" over a small label.
    private func periodProgress(count: Int, target: Int, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(min(count, target))/\(target)")
                .font(Theme.headingFont(size: 22, weight: .medium))
                .foregroundStyle(
                    count >= target
                        ? Theme.ndTextDisplay.resolve(for: colorScheme)
                        : Theme.ndTextSecondary.resolve(for: colorScheme)
                )
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.labelFont(size: 8))
                .tracking(8 * 0.04)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
    }

    // MARK: - Circle Grid

    /// Spacing scales with circle size (keeps the standard 10:30 ratio) so the
    /// zoomed-out grid stays proportional.
    private func spacing(for size: CGFloat) -> CGFloat { max(2, size / 3) }

    /// The dot size for the continuous view: standard 30pt, or — when "Show all
    /// entries" is on — the largest size at which every cell fits the viewport
    /// without scrolling (clamped to `minCircleSize`).
    private func continuousCircleSize(viewport: CGSize) -> CGFloat {
        guard showAll else { return Self.circleSize }
        let n = cells.count
        guard n > 0 else { return Self.circleSize }

        let availW = viewport.width - Theme.spaceMD * 2
        // Vertical budget = viewport minus the top+bottom content padding. Labels
        // are hidden in this mode, so each row costs only (size + spacing).
        let availH = viewport.height - Theme.spaceLG - Theme.space2XL
        guard availW > 0, availH > 0 else { return Self.minCircleSize }

        var size = Self.circleSize
        while size > Self.minCircleSize {
            let s = spacing(for: size)
            let cols = max(1, Int((availW + s) / (size + s)))
            let rows = Int(ceil(Double(n) / Double(cols)))
            let neededH = CGFloat(rows) * (size + s) - s
            if neededH <= availH { return size }
            size -= 1
        }
        return Self.minCircleSize
    }

    /// The dot size for the week grid: standard 30pt, or — when "Show all
    /// entries" is on — the largest size at which every week row fits the
    /// viewport height (the week grid is 7-wide, so only the row count varies).
    private func weekCircleSize(viewport: CGSize) -> CGFloat {
        guard showAll else { return Self.circleSize }
        let rows = weekRows.count
        guard rows > 0 else { return Self.circleSize }

        let availH = viewport.height - Theme.spaceLG - Theme.space2XL
        guard availH > 0 else { return Self.minCircleSize }
        // The weekday header row (~14pt) sits above the week rows; each week row
        // costs (size + spacing). Gutter labels are hidden in this mode.
        let headerAllowance: CGFloat = 16

        var size = Self.circleSize
        while size > Self.minCircleSize {
            let s = spacing(for: size)
            let neededH = headerAllowance + CGFloat(rows) * (size + s)
            if neededH <= availH { return size }
            size -= 1
        }
        return Self.minCircleSize
    }

    private func circleGrid(circleSize: CGFloat) -> some View {
        let gridSpacing = spacing(for: circleSize)
        let columns = [
            GridItem(
                .adaptive(minimum: circleSize, maximum: circleSize),
                spacing: gridSpacing,
                alignment: .center
            )
        ]
        // Bird's-eye "show all" mode drops the per-dot date labels for density.
        let showLabels = !showAll
        let labelMap = showLabels ? dateIndicators(for: cells) : [:]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                if showLabels {
                    VStack(spacing: 3) {
                        if let label = labelMap[i] {
                            Text(label)
                                .font(Theme.labelFont(size: 8))
                                .tracking(8 * 0.04)
                                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(height: Self.dateHeaderHeight)
                        } else {
                            Color.clear.frame(height: Self.dateHeaderHeight)
                        }
                        circle(for: cell, size: circleSize)
                    }
                } else {
                    circle(for: cell, size: circleSize)
                }
            }
        }
    }

    // MARK: - Date indicators

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Returns a map of cell-index → label: "TODAY" over the add-button, then a
    /// date every 7 calendar days going back. Since the row is now a continuous
    /// day timeline, these marks land at even intervals. Empty streaks
    /// (add-button only) get no label, honoring the minimal default.
    private func dateIndicators(for cells: [StreakCell]) -> [Int: String] {
        guard !list.streakEntries.isEmpty else { return [:] }
        let cal = Calendar.current

        // day → index of the first cell on that day
        var dayToFirstIdx: [Date: Int] = [:]
        for (i, cell) in cells.enumerated() {
            let d = cellDay(cell)
            if dayToFirstIdx[d] == nil { dayToFirstIdx[d] = i }
        }

        let todayStart = cal.startOfDay(for: Date())
        let earliest = cells.map(cellDay).min() ?? todayStart

        var result: [Int: String] = [:]
        var target = todayStart
        while target >= earliest {
            if let idx = dayToFirstIdx[target] {
                result[idx] = cal.isDateInToday(target)
                    ? "TODAY"
                    : Self.shortDateFmt.string(from: target).uppercased()
            }
            guard let prev = cal.date(byAdding: .day, value: -7, to: target) else { break }
            target = prev
        }
        return result
    }

    @ViewBuilder
    private func circle(for cell: StreakCell, size: CGFloat = Self.circleSize) -> some View {
        switch cell {
        case .add:
            // Persistent leading tap-target — always logs today.
            Button {
                list.addStreakEntry()
                Theme.mediumHaptic()
                Analytics.streakLogged(listTitle: list.title)
            } label: {
                circleShape(
                    fill: .clear,
                    stroke: Theme.ndTextDisplay.resolve(for: colorScheme),
                    lineWidth: 1.5,
                    size: size
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section("Today") {
                    Button {
                        list.addStreakEntry()
                        Theme.mediumHaptic()
                        Analytics.streakLogged(listTitle: list.title)
                    } label: {
                        Label("Log Today", systemImage: "checkmark.circle")
                    }
                }
            }

        case let .entry(index):
            let entry = list.streakEntries.indices.contains(index)
                ? list.streakEntries[index]
                : StreakEntry(date: Date(), filled: false)
            Button {
                list.toggleStreakEntry(at: index)
                entry.filled ? Theme.lightHaptic() : Theme.mediumHaptic()
            } label: {
                circleShape(
                    fill: entry.filled ? Theme.ndTextDisplay.resolve(for: colorScheme) : .clear,
                    stroke: entry.filled ? .clear : Theme.ndTextDisplay.resolve(for: colorScheme),
                    lineWidth: entry.filled ? 0 : 1,
                    size: size
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section(Self.dateLabel(for: entry.date)) {
                    Button {
                        pendingDate = entry.date
                        editingIndex = index
                    } label: {
                        Label("Edit Date", systemImage: "calendar")
                    }
                    Button(role: .destructive) {
                        list.removeStreakEntry(at: index)
                        Theme.lightHaptic()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }

        case let .gap(day):
            // A calendar day with no entry — tap to log that day.
            Button {
                list.addStreakEntry(day)
                Theme.mediumHaptic()
                Analytics.streakLogged(listTitle: list.title)
            } label: {
                circleShape(
                    fill: .clear,
                    stroke: Theme.ndTextDisplay.resolve(for: colorScheme),
                    lineWidth: 1,
                    size: size
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section(Self.dateLabel(for: day)) {
                    Button {
                        list.addStreakEntry(day)
                        Theme.mediumHaptic()
                        Analytics.streakLogged(listTitle: list.title)
                    } label: {
                        Label("Log This Day", systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    private func circleShape(
        fill: Color,
        stroke: Color,
        lineWidth: CGFloat,
        size: CGFloat = Self.circleSize
    ) -> some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(stroke, lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
    }

    /// Filled completions on `date` — the numerator for X-per-day partial fills.
    private func dayCompletionCount(_ date: Date) -> Int {
        let cal = Calendar.current
        return list.streakEntries.filter { $0.filled && cal.isDate($0.date, inSameDayAs: date) }.count
    }

    /// Removes a single filled completion on `date` (the "remove one" path for
    /// count-based cadences in the week grid).
    private func removeOneCompletion(on date: Date) {
        let cal = Calendar.current
        if let idx = list.streakEntries.lastIndex(where: {
            $0.filled && cal.isDate($0.date, inSameDayAs: date)
        }) {
            list.removeStreakEntry(at: idx)
        }
    }

    /// A dot that fills proportionally toward `target` — solid once met. Used in
    /// the week grid for count-based cadences (X/day) so a 2-of-3 day reads as
    /// two-thirds of an arc rather than a binary on/off.
    private func progressCircle(count: Int, target: Int, isToday: Bool, size: CGFloat = Self.circleSize) -> some View {
        let fraction = target > 0 ? min(1, Double(count) / Double(target)) : 0
        let met = count >= target
        let accent = Theme.ndTextDisplay.resolve(for: colorScheme)
        // Scale the arc weight down with the dot so it doesn't swamp small cells.
        let arcWidth = max(1, size / 12)
        return ZStack {
            if met {
                Circle().fill(accent)
            } else {
                Circle().strokeBorder(accent.opacity(0.25), lineWidth: isToday ? 1.5 : 1)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(arcWidth * 0.6)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Week grid (Monday-aligned)

    /// One cell in the week grid — a real day, or a blank spacer for days
    /// outside the [earliest, today] range that keep the weekday columns aligned.
    private enum WeekCell: Equatable {
        case day(Date)
        case blank(Int)
    }

    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]
    private static let weekGutter: CGFloat = 38

    /// One row in the grid: its first in-range day (anchor) + seven Mon→Sun cells.
    private struct WeekRow: Identifiable {
        let id: Int
        let anchor: Date
        let containsToday: Bool
        let cells: [WeekCell]
    }

    private var weekRows: [WeekRow] {
        Self.buildWeeks(entries: list.streakEntries, today: Date())
    }

    /// Oldest row first (top) so the grid reads top→bottom = past→present. Rows
    /// break on Mondays **and** the 1st of a month, so a month always starts a
    /// fresh row with its first day in the correct weekday column (standard
    /// month-calendar layout). Empty weekday slots render as blanks.
    private static func buildWeeks(entries: [StreakEntry], today: Date) -> [WeekRow] {
        let cal = Calendar(identifier: .iso8601) // firstWeekday == Monday
        let todayStart = cal.startOfDay(for: today)
        let earliest = entries.map { cal.startOfDay(for: $0.date) }.min() ?? todayStart
        let start = min(earliest, todayStart)

        // ISO weekday: 1=Sun…7=Sat → Mon-based column 0…6.
        func column(_ date: Date) -> Int { (cal.component(.weekday, from: date) + 5) % 7 }

        var rows: [WeekRow] = []
        var rowID = 0
        var slots = [Date?](repeating: nil, count: 7)
        var anchor: Date?
        var containsToday = false

        var day = start
        while day <= todayStart {
            let col = column(day)
            let breakRow = (col == 0 || cal.component(.day, from: day) == 1) && anchor != nil
            if breakRow {
                let cells = slots.enumerated().map { i, d in d.map { WeekCell.day($0) } ?? WeekCell.blank(i) }
                rows.append(WeekRow(id: rowID, anchor: anchor!, containsToday: containsToday, cells: cells))
                rowID += 1
                slots = [Date?](repeating: nil, count: 7)
                anchor = nil
                containsToday = false
            }
            slots[col] = day
            if anchor == nil { anchor = day }
            if cal.isDate(day, inSameDayAs: todayStart) { containsToday = true }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if let anchor {
            let cells = slots.enumerated().map { i, d in d.map { WeekCell.day($0) } ?? WeekCell.blank(i) }
            rows.append(WeekRow(id: rowID, anchor: anchor, containsToday: containsToday, cells: cells))
        }
        return rows
    }

    private func weekLabel(for row: WeekRow) -> String {
        row.containsToday ? "THIS WK" : Self.shortDateFmt.string(from: row.anchor).uppercased()
    }

    private func weekGrid(circleSize: CGFloat) -> some View {
        let gridSpacing = spacing(for: circleSize)
        // Fixed label column + 7 flexible day columns, so the circles spread
        // across the full width instead of clustering at intrinsic size.
        let columns = [GridItem(.fixed(Self.weekGutter), alignment: .leading)]
            + Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7)
        // "Show all" compresses every week onto one screen — drop the per-week
        // gutter labels so row height is driven by the (shrunk) dots alone.
        let showLabels = !showAll

        return LazyVGrid(columns: columns, alignment: .center, spacing: gridSpacing) {
            // Weekday header
            Color.clear.frame(height: 1)
            ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(Theme.labelFont(size: 8))
                    .tracking(8 * 0.04)
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            // Week rows, newest first — each labeled with its week-of date
            ForEach(weekRows) { week in
                Text(showLabels ? weekLabel(for: week) : "")
                    .font(Theme.labelFont(size: 8))
                    .tracking(8 * 0.04)
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.weekGutter, alignment: .leading)
                ForEach(Array(week.cells.enumerated()), id: \.offset) { _, cell in
                    weekCell(cell, size: circleSize)
                }
            }
        }
    }

    @ViewBuilder
    private func weekCell(_ cell: WeekCell, size: CGFloat = Self.circleSize) -> some View {
        switch cell {
        case .blank:
            Color.clear.frame(width: size, height: size)

        case let .day(date):
            let isToday = Calendar.current.isDateInToday(date)
            // Per-DAY dot target: the cadence target only for day-based cadences
            // (X/day). Weekly cadences measure per week, so a single day-dot is
            // binary (did you log that day) — otherwise every logged day would
            // render a partial N-of-week arc.
            let target = cadence.dailyTarget
            if target > 1 {
                // Count-based cadence: tap adds one completion toward the target;
                // the dot fills proportionally.
                let count = dayCompletionCount(date)
                Button {
                    list.addStreakEntry(date)
                    Theme.mediumHaptic()
                    Analytics.streakLogged(listTitle: list.title)
                } label: {
                    progressCircle(count: count, target: target, isToday: isToday, size: size)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Section(Self.dateLabel(for: date)) {
                        Text("\(count)/\(target) logged")
                        Button {
                            list.addStreakEntry(date)
                            Theme.mediumHaptic()
                            Analytics.streakLogged(listTitle: list.title)
                        } label: {
                            Label("Add one", systemImage: "plus.circle")
                        }
                        Button(role: .destructive) {
                            removeOneCompletion(on: date)
                            Theme.lightHaptic()
                        } label: {
                            Label("Remove one", systemImage: "minus.circle")
                        }
                        .disabled(count == 0)
                    }
                }
            } else {
                let logged = list.isStreakDayLogged(date)
                Button {
                    list.setStreakDay(date, filled: !logged)
                    logged ? Theme.lightHaptic() : Theme.mediumHaptic()
                    if !logged { Analytics.streakLogged(listTitle: list.title) }
                } label: {
                    circleShape(
                        fill: logged ? Theme.ndTextDisplay.resolve(for: colorScheme) : .clear,
                        stroke: logged ? .clear : Theme.ndTextDisplay.resolve(for: colorScheme),
                        lineWidth: logged ? 0 : (isToday ? 1.5 : 1),
                        size: size
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Section(Self.dateLabel(for: date)) {
                        Button {
                            list.setStreakDay(date, filled: !logged)
                            logged ? Theme.lightHaptic() : Theme.mediumHaptic()
                        } label: {
                            Label(
                                logged ? "Unmark" : "Mark done",
                                systemImage: logged ? "circle" : "checkmark.circle"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Date label

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        return f
    }()

    static func dateLabel(for day: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = dateFormatter
        if cal.component(.year, from: day) == cal.component(.year, from: now) {
            f.dateFormat = "EEE, MMM d"
        } else {
            f.dateFormat = "MMM d, ʼyy"
        }
        return f.string(from: day)
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        Menu {
            Button {
                weekView.toggle()
            } label: {
                Label(
                    weekView ? "Continuous view" : "Sort by week",
                    systemImage: weekView ? "square.grid.3x1.below.line.grid.1x2" : "calendar"
                )
            }
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { showAll.toggle() }
            } label: {
                Label(
                    showAll ? "Standard size" : "Show all entries",
                    systemImage: showAll
                        ? "arrow.up.left.and.arrow.down.right"
                        : "arrow.down.right.and.arrow.up.left"
                )
            }
            Divider()
            Button {
                showCadenceSheet = true
            } label: {
                Label("Cadence: \(list.streakCadence?.displayLabel ?? "Daily")", systemImage: "repeat")
            }
            Divider()
            Button {
                renameText = list.title
                showRename = true
            } label: {
                Label("Rename List", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete List", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .frame(width: 36, height: 36)
        }
    }
}

// MARK: - Date Edit Sheet

/// Day-only date picker for re-dating a streak entry.
struct StreakDateEditSheet: View {
    @Binding var date: Date
    var onCommit: () -> Void
    var onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
                Spacer()
                Button(action: onCommit) {
                    Text("SAVE")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            Text("DATE")
                .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                .padding(.horizontal, Theme.spaceMD)

            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, Theme.spaceMD)

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
    }
}

// MARK: - Cadence Edit Sheet

/// Change an existing streak's cadence. Edits apply live (the parent's
/// `onChange(of: list)` persists), so DONE just dismisses.
struct StreakCadenceEditSheet: View {
    @Binding var cadence: StreakCadence
    var onDone: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("DONE")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            CadencePicker(cadence: $cadence)
                .padding(.horizontal, Theme.spaceMD)

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
    }
}
