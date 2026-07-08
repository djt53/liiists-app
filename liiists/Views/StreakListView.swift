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
    @State private var editingIndex: Int?
    @State private var pendingDate = Date()

    private static let circleSize: CGFloat = 30
    private static let circleSpacing: CGFloat = 10
    private static let dateHeaderHeight: CGFloat = 12

    init(list: ItemList) {
        _list = State(initialValue: list)
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
                onCancel: {
                    editingIndex = nil
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
                Text("\(list.streakLoggedCount) LOGGED")
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
    private func circle(for cell: StreakCell) -> some View {
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
                    lineWidth: 1.5
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
                    lineWidth: entry.filled ? 0 : 1
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
                    lineWidth: 1
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
