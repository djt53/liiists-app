import SwiftUI

/// Streak view: a wrapped, newest-first sequence of circles. Each filled
/// circle is one completion on a given day; the dates are hidden by default.
///
/// The render sequence runs from the earliest logged day up to today:
/// - Today always leads (top-left) with an empty tap-target, followed by any
///   completions logged today — so you can log more than once a day.
/// - Each earlier day shows one filled circle per completion, or — if nothing
///   was logged that day — a single empty circle that persists as a gap.
///
/// Tap an empty circle to log that day. Long-press any circle to reveal its
/// date and edit, remove, or backfill it.
struct StreakListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var editingDay: Date?
    @State private var editingEntryIndex: Int?
    @State private var pendingDate = Date()

    private static let circleSize: CGFloat = 30
    private static let circleSpacing: CGFloat = 10
    private static let dateHeaderHeight: CGFloat = 12

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    // MARK: - Cell model

    /// One circle per calendar day for past days; today gets a persistent empty
    /// tap-target plus one indexed filled cell per logged entry so you can keep
    /// tapping to log multiple completions. `entryIndex` is nil for past-day
    /// filled cells (remove targets the whole day).
    private enum StreakCell: Equatable {
        case filled(day: Date, entryIndex: Int?)
        case empty(day: Date)

        var day: Date {
            switch self {
            case let .filled(day, _): return day
            case let .empty(day): return day
            }
        }
    }

    private var cells: [StreakCell] {
        Self.buildCells(entries: list.streakEntries, displayFrom: list.streakDisplayFrom)
    }

    /// Builds the newest-first cell sequence. Today uses the original multi-cell
    /// model (persistent empty tap-target + one indexed filled cell per log) so
    /// repeated taps keep adding entries. Past days use one-cell-per-day toggle.
    private static func buildCells(
        entries: [Date],
        displayFrom: Date? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [StreakCell] {
        let todayStart = calendar.startOfDay(for: today)

        var indicesByDay: [Date: [Int]] = [:]
        for (i, entry) in entries.enumerated() {
            indicesByDay[calendar.startOfDay(for: entry), default: []].append(i)
        }
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0) })

        let entriesMin = entries.map { calendar.startOfDay(for: $0) }.min()
        let effectiveMin = ([entriesMin, displayFrom] as [Date?]).compactMap { $0 }.min()
        let start = min(effectiveMin ?? todayStart, todayStart)

        var result: [StreakCell] = []
        var day = todayStart
        while day >= start {
            if calendar.isDate(day, inSameDayAs: todayStart) {
                // Today: persistent tap-target first, then one filled cell per log
                result.append(.empty(day: todayStart))
                for i in (indicesByDay[todayStart] ?? []) {
                    result.append(.filled(day: todayStart, entryIndex: i))
                }
            } else if loggedDays.contains(day) {
                // Past logged day: single filled cell, whole-day removal on tap
                result.append(.filled(day: day, entryIndex: nil))
            } else {
                result.append(.empty(day: day))
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                circleGrid
                    .padding(.horizontal, Theme.spaceMD)
                    .padding(.top, Theme.spaceLG)
                    .padding(.bottom, Theme.space2XL)
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
            get: { editingDay != nil },
            set: { if !$0 { editingDay = nil } }
        )) {
            StreakDateEditSheet(
                date: $pendingDate,
                onCommit: {
                    if let original = editingDay {
                        if let idx = editingEntryIndex {
                            list.updateStreakEntry(at: idx, to: pendingDate)
                        } else {
                            list.moveStreakEntry(from: original, to: pendingDate)
                        }
                        Theme.lightHaptic()
                    }
                    editingDay = nil
                    editingEntryIndex = nil
                },
                onCancel: {
                    editingDay = nil
                    editingEntryIndex = nil
                }
            )
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
        }
        .enableSwipeBack()
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
                Text("\(list.streakEntries.count) LOGGED")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            Spacer()
            overflowMenu
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.top, Theme.spaceLG)
        .padding(.bottom, Theme.spaceMD)
    }

    // MARK: - Circle Grid

    private var circleGrid: some View {
        let columns = [
            GridItem(
                .adaptive(minimum: Self.circleSize, maximum: Self.circleSize),
                spacing: Self.circleSpacing,
                alignment: .center
            )
        ]
        let labelMap = dateIndicators(for: cells)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.circleSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
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
                    circle(for: cell)
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

    /// Returns a map of cell-index → label for the first filled cell and
    /// every 7 calendar days before it, anchored on that cell's date.
    private func dateIndicators(for cells: [StreakCell]) -> [Int: String] {
        guard !cells.isEmpty else { return [:] }
        let cal = Calendar.current

        guard let anchorIdx = cells.indices.first(where: {
            if case .filled = cells[$0] { return true }
            return false
        }) else { return [:] }

        let anchorDay = cal.startOfDay(for: cells[anchorIdx].day)
        let earliestDay = cal.startOfDay(for: cells.last!.day)

        // day → index of first cell on that day
        var dayToFirstIdx: [Date: Int] = [:]
        for (i, cell) in cells.enumerated() {
            let d = cal.startOfDay(for: cell.day)
            if dayToFirstIdx[d] == nil { dayToFirstIdx[d] = i }
        }

        var result: [Int: String] = [:]
        var target = anchorDay
        while target >= earliestDay {
            if let idx = dayToFirstIdx[target] {
                let label = cal.isDateInToday(target)
                    ? "TODAY"
                    : Self.shortDateFmt.string(from: target).uppercased()
                result[idx] = label
            }
            guard let prev = cal.date(byAdding: .day, value: -7, to: target) else { break }
            target = prev
        }
        return result
    }

    @ViewBuilder
    private func circle(for cell: StreakCell) -> some View {
        let isToday = Calendar.current.isDateInToday(cell.day)

        switch cell {
        case let .filled(day, entryIndex):
            Button {
                if let idx = entryIndex {
                    list.removeStreakEntry(at: idx)
                } else {
                    list.removeStreakEntriesForDay(day)
                }
                Theme.lightHaptic()
            } label: {
                circleShape(
                    fill: Theme.ndTextDisplay.resolve(for: colorScheme),
                    stroke: .clear,
                    lineWidth: 0
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section(Self.dateLabel(for: day)) {
                    Button {
                        pendingDate = day
                        editingDay = day
                        editingEntryIndex = entryIndex
                    } label: {
                        Label("Edit Date", systemImage: "calendar")
                    }
                    Button(role: .destructive) {
                        if let idx = entryIndex {
                            list.removeStreakEntry(at: idx)
                        } else {
                            list.removeStreakEntriesForDay(day)
                        }
                        Theme.lightHaptic()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }

        case let .empty(day):
            Button {
                list.addStreakEntry(day)
                Theme.mediumHaptic()
                Analytics.streakLogged(listTitle: list.title)
            } label: {
                circleShape(
                    fill: .clear,
                    stroke: Theme.ndTextDisplay.resolve(for: colorScheme),
                    lineWidth: isToday ? 1.5 : 1
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section(isToday ? "Today" : Self.dateLabel(for: day)) {
                    Button {
                        list.addStreakEntry(day)
                        Theme.mediumHaptic()
                        Analytics.streakLogged(listTitle: list.title)
                    } label: {
                        Label(isToday ? "Log Today" : "Log This Day", systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    private func circleShape(fill: Color, stroke: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(stroke, lineWidth: lineWidth)
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
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
