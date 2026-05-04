import SwiftUI

/// Single-habit streak view: stat pills at top, then a wrapping grid of
/// small circles starting with today (top-left) and growing as days pass.
/// Tap any circle to log/unlog that day.
struct StreakListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

    private static let circleSize: CGFloat = 28
    private static let circleSpacing: CGFloat = 8

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    private var cadence: StreakCadence {
        list.streakCadence ?? .daily
    }

    private var stats: StreakStatsResult {
        StreakStats.compute(entries: list.streakEntries, cadence: cadence)
    }

    /// All days that should appear as circles. Newest first.
    /// Range: createdDate (or today if missing) → today.
    private var visibleDays: [Date] {
        let start = list.createdDate ?? Date()
        return StreakStats.eligibleDays(from: start, cadence: cadence)
    }

    private var entryDaySet: Set<Date> {
        Set(list.streakEntries.map { Calendar.current.startOfDay(for: $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            statsRow
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
                Text(cadence.displayLabel.uppercased())
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            Spacer()
            overflowMenu
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.top, Theme.spaceLG)
        .padding(.bottom, Theme.spaceMD)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: Theme.spaceLG) {
            statPill(
                icon: "flame.fill",
                value: "\(stats.currentStreak)",
                label: "current",
                color: stats.currentStreak > 0 ? Theme.ndAccent : Theme.ndTextSecondary.resolve(for: colorScheme)
            )
            statPill(
                icon: "trophy.fill",
                value: "\(stats.longestStreak)",
                label: "best",
                color: Theme.ndWarning
            )
            statPill(
                icon: "calendar",
                value: "\(stats.thisWeekCount)/\(stats.thisWeekTarget)",
                label: "this week",
                color: Theme.ndInteractive.resolve(for: colorScheme)
            )
            Spacer()
        }
        .padding(.horizontal, Theme.spaceMD)
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: Theme.space2XS) {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(value)
                    .font(Theme.monoFont(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
            }
            Text(label.uppercased())
                .font(Theme.labelFont(size: 9))
                .tracking(9 * 0.06)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
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
            ForEach(visibleDays, id: \.timeIntervalSince1970) { day in
                circle(for: day)
            }
        }
    }

    @ViewBuilder
    private func circle(for day: Date) -> some View {
        let isLogged = entryDaySet.contains(Calendar.current.startOfDay(for: day))
        let isToday = Calendar.current.isDate(day, inSameDayAs: Date())
        let fill: Color = isLogged
            ? (isToday ? Theme.ndAccent : Theme.ndSuccess)
            : .clear
        let stroke: Color = isToday
            ? Theme.ndAccent
            : Theme.ndBorderVisible.resolve(for: colorScheme)

        Button {
            list.toggleStreakDay(day)
            Theme.mediumHaptic()
            Analytics.streakLogged(listTitle: list.title)
        } label: {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: isLogged ? 0 : 1)
            }
            .frame(width: Self.circleSize, height: Self.circleSize)
        }
        .buttonStyle(.plain)
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
