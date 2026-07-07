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
    @State private var editingIndex: Int?
    @State private var pendingDate = Date()

    private static let circleSize: CGFloat = 30
    private static let circleSpacing: CGFloat = 10

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    // MARK: - Cell model

    /// One rendered circle. `filled` carries the entry's index into
    /// `streakEntries` so edit/remove can target it; `empty` is a tappable
    /// slot for a day with no completion.
    private enum StreakCell: Equatable {
        case filled(entryIndex: Int, day: Date)
        case empty(day: Date)

        var day: Date {
            switch self {
            case let .filled(_, day): return day
            case let .empty(day): return day
            }
        }
    }

    private var cells: [StreakCell] {
        Self.buildCells(entries: list.streakEntries)
    }

    /// Build the newest-first render sequence. Pure so it stays easy to reason
    /// about: today leads with an empty tap-target plus today's completions,
    /// then each earlier day down to the first logged day.
    private static func buildCells(
        entries: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [StreakCell] {
        let todayStart = calendar.startOfDay(for: today)

        var indicesByDay: [Date: [Int]] = [:]
        for (i, entry) in entries.enumerated() {
            indicesByDay[calendar.startOfDay(for: entry), default: []].append(i)
        }

        let days = entries.map { calendar.startOfDay(for: $0) }
        let start = min(days.min() ?? todayStart, todayStart)
        // Cover future-dated entries too (a manual edit can push an entry past
        // today) so they never silently drop out of the grid.
        let top = max(days.max() ?? todayStart, todayStart)

        var result: [StreakCell] = []
        var day = top
        while day >= start {
            let idxs = indicesByDay[day] ?? []
            if calendar.isDate(day, inSameDayAs: todayStart) {
                // Leading empty tap-target, then today's completions.
                result.append(.empty(day: day))
                for i in idxs { result.append(.filled(entryIndex: i, day: day)) }
            } else if idxs.isEmpty {
                // A past day with no completion persists as an empty gap.
                // Future empty days (from a forward-dated edit) are skipped.
                if day < todayStart { result.append(.empty(day: day)) }
            } else {
                for i in idxs { result.append(.filled(entryIndex: i, day: day)) }
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
                onCancel: { editingIndex = nil }
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
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.circleSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                circle(for: cell)
            }
        }
    }

    @ViewBuilder
    private func circle(for cell: StreakCell) -> some View {
        let isToday = Calendar.current.isDateInToday(cell.day)

        switch cell {
        case let .filled(entryIndex, day):
            Button {
                // Filled circles have no primary tap action; editing is via
                // long-press. Keep the tap area alive for a soft haptic.
                Theme.lightHaptic()
            } label: {
                circleShape(
                    fill: isToday ? Theme.ndAccent : Theme.ndSuccess,
                    stroke: .clear,
                    lineWidth: 0
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section(Self.dateLabel(for: day)) {
                    Button {
                        pendingDate = day
                        editingIndex = entryIndex
                    } label: {
                        Label("Edit Date", systemImage: "calendar")
                    }
                    Button(role: .destructive) {
                        list.removeStreakEntry(at: entryIndex)
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
                    stroke: isToday
                        ? Theme.ndAccent
                        : Theme.ndBorderVisible.resolve(for: colorScheme),
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
