import SwiftUI

struct StreakListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showAddHabit = false
    @State private var newHabitName = ""
    @State private var newHabitCadence: StreakCadence = .daily
    @FocusState private var isAddHabitFocused: Bool

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                Text(list.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
                Spacer()
                Button {
                    showAddHabit = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 36, height: 36)
                }
                overflowMenu
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)
            .padding(.bottom, Theme.spaceMD)

            // Sections
            if list.streakSections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spaceLG) {
                        ForEach(Array(list.streakSections.enumerated()), id: \.element.id) { index, section in
                            StreakSectionCard(
                                section: Binding(
                                    get: { list.streakSections[index] },
                                    set: { list.streakSections[index] = $0 }
                                ),
                                onToggleToday: {
                                    list.streakSections[index].toggleToday()
                                    Theme.mediumHaptic()
                                },
                                onDelete: {
                                    list.streakSections.remove(at: index)
                                    Theme.lightHaptic()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.spaceMD)
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
            Text("This will permanently delete \"\(list.title)\" and all its streaks.")
        }
        .sheet(isPresented: $showAddHabit) {
            addHabitSheet
        }
        .enableSwipeBack()
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.spaceMD) {
            Spacer()
            Image(systemName: "flame")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Text("Add your first streak")
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Button {
                showAddHabit = true
            } label: {
                Text("ADD STREAK")
                    .font(Theme.labelFont(size: 13))
                    .tracking(13 * 0.06)
                    .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                    .padding(.horizontal, Theme.spaceLG)
                    .padding(.vertical, Theme.spaceSM)
                    .background(Theme.ndTextPrimary.resolve(for: colorScheme))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add Habit Sheet

    private var addHabitSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    newHabitName = ""
                    newHabitCadence = .daily
                    showAddHabit = false
                } label: {
                    Text("CANCEL")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
                Spacer()
                Button {
                    let trimmed = newHabitName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    list.streakSections.append(StreakSection(name: trimmed, cadence: newHabitCadence))
                    Theme.mediumHaptic()
                    newHabitName = ""
                    newHabitCadence = .daily
                    showAddHabit = false
                } label: {
                    Text("ADD")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(
                            newHabitName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.ndTextDisabled.resolve(for: colorScheme)
                                : Theme.ndBlack.resolve(for: colorScheme)
                        )
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(
                            newHabitName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.ndSurfaceRaised.resolve(for: colorScheme)
                                : Theme.ndTextPrimary.resolve(for: colorScheme)
                        )
                        .clipShape(Capsule())
                }
                .disabled(newHabitName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            // Name input
            VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Text("STREAK NAME")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                TextField("e.g. Workouts", text: $newHabitName)
                    .font(Theme.headingFont(size: Theme.headingSize))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .focused($isAddHabitFocused)
                    .submitLabel(.done)
                    .padding(.bottom, Theme.spaceSM)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(
                                isAddHabitFocused
                                    ? Theme.ndTextPrimary.resolve(for: colorScheme)
                                    : Theme.ndBorderVisible.resolve(for: colorScheme)
                            )
                    }
            }
            .padding(.horizontal, Theme.spaceMD)

            Spacer().frame(height: Theme.spaceXL)

            // Cadence picker
            VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Text("CADENCE")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

                HStack(spacing: 0) {
                    cadenceButton(label: "DAILY", cadence: .daily)
                    cadenceButton(label: "WEEKDAYS", cadence: .weekdays)
                    cadenceButton(label: "3/WEEK", cadence: .perWeek(3))
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                // Custom N/week picker when perWeek is selected
                if case .perWeek = newHabitCadence {
                    HStack(spacing: Theme.spaceSM) {
                        Text("TIMES PER WEEK")
                            .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                        Spacer()
                        HStack(spacing: Theme.spaceSM) {
                            ForEach(1...7, id: \.self) { n in
                                Button {
                                    withAnimation(.easeOut(duration: Theme.microDuration)) {
                                        newHabitCadence = .perWeek(n)
                                    }
                                } label: {
                                    Text("\(n)")
                                        .font(Theme.monoFont(size: 14))
                                        .frame(width: 28, height: 28)
                                        .foregroundStyle(
                                            cadenceWeekCount == n
                                                ? Theme.ndBlack.resolve(for: colorScheme)
                                                : Theme.ndTextSecondary.resolve(for: colorScheme)
                                        )
                                        .background(
                                            cadenceWeekCount == n
                                                ? Theme.ndTextDisplay.resolve(for: colorScheme)
                                                : .clear
                                        )
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, Theme.spaceSM)
                }
            }
            .padding(.horizontal, Theme.spaceMD)

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
        .onAppear { isAddHabitFocused = true }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var cadenceWeekCount: Int {
        if case .perWeek(let n) = newHabitCadence { return n }
        return 3
    }

    private func cadenceButton(label: String, cadence: StreakCadence) -> some View {
        let isActive: Bool = {
            switch (newHabitCadence, cadence) {
            case (.daily, .daily), (.weekdays, .weekdays): return true
            case (.perWeek, .perWeek): return true
            default: return false
            }
        }()
        return Button {
            withAnimation(.easeOut(duration: Theme.microDuration)) {
                newHabitCadence = cadence
            }
        } label: {
            Text(label)
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.06)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(
                    isActive
                        ? Theme.ndBlack.resolve(for: colorScheme)
                        : Theme.ndTextSecondary.resolve(for: colorScheme)
                )
                .background(
                    isActive
                        ? Theme.ndTextDisplay.resolve(for: colorScheme)
                        : .clear
                )
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

// MARK: - Streak Section Card

struct StreakSectionCard: View {
    @Binding var section: StreakSection
    var onToggleToday: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var stats: StreakStatsResult {
        StreakStats.compute(for: section)
    }

    private var gridRows: [[GridDot]] {
        StreakStats.gridDots(for: section, weeks: 8)
    }

    private var loggedToday: Bool {
        section.isLoggedToday()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceMD) {
            // Section header + delete
            HStack {
                Text(section.name.uppercased())
                    .font(Theme.labelFont(size: 13))
                    .tracking(13 * 0.08)
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                Text(section.cadence.displayLabel.uppercased())
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove Streak", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(width: 28, height: 28)
                }
            }

            // Stats row
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

            // Dot grid
            dotGrid

            // Log today button
            Button {
                onToggleToday()
            } label: {
                HStack(spacing: Theme.spaceSM) {
                    Image(systemName: loggedToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(loggedToday ? Theme.ndSuccess : Theme.ndTextSecondary.resolve(for: colorScheme))
                    Text(loggedToday ? "LOGGED TODAY" : "LOG TODAY")
                        .font(Theme.labelFont(size: 12))
                        .tracking(12 * 0.06)
                        .foregroundStyle(
                            loggedToday
                                ? Theme.ndSuccess
                                : Theme.ndTextPrimary.resolve(for: colorScheme)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    loggedToday
                        ? Theme.ndSuccess.opacity(0.1)
                        : Theme.ndSurfaceRaised.resolve(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spaceMD)
        .background(Theme.ndSurface.resolve(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    // MARK: - Stat Pill

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

    // MARK: - Dot Grid

    private var dotGrid: some View {
        VStack(spacing: 3) {
            // Day labels
            HStack(spacing: 3) {
                let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(Theme.labelFont(size: 8))
                        .foregroundStyle(Theme.ndTextDisabled.resolve(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(gridRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row) { dot in
                        dotView(dot)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dotView(_ dot: GridDot) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.startOfDay(for: dot.date) == today
        let isFuture = dot.date > today

        if isFuture {
            // Future: invisible placeholder
            Circle()
                .fill(.clear)
        } else if dot.completed {
            // Filled dot
            Circle()
                .fill(isToday ? Theme.ndAccent : Theme.ndSuccess)
        } else if dot.isExpected {
            // Expected but missed: outline
            Circle()
                .strokeBorder(
                    isToday
                        ? Theme.ndAccent.opacity(0.5)
                        : Theme.ndBorderVisible.resolve(for: colorScheme),
                    lineWidth: 1
                )
        } else {
            // Not expected (e.g. weekend for weekdays): very subtle
            Circle()
                .fill(Theme.ndSurfaceRaised.resolve(for: colorScheme))
        }
    }
}
