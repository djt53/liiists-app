import SwiftUI

/// Streak detail on the watch: a large "Log Today" circle up top, the current
/// streak stat, and the 5 most recent completions. Logging is a single tap that
/// round-trips to the iPhone (which owns the markdown write); the circle updates
/// optimistically so the wrist feels instant.
struct WatchStreakView: View {
    let entry: WatchCatalogEntry

    @EnvironmentObject var catalog: WatchCatalogStore
    @EnvironmentObject var phone: WatchPhoneClient

    /// Absolute optimistic override for today's completion count — set on tap,
    /// cleared to `nil` (adopting server truth) whenever the catalog refreshes.
    @State private var optimisticToday: Int?

    /// Live snapshot from the catalog, falling back to the value we navigated in
    /// with until the first refresh lands.
    private var current: WatchCatalogEntry {
        catalog.entry(filename: entry.filename) ?? entry
    }

    private var streak: WatchStreakInfo? { current.streak }

    /// The target for *today's* circle. Weekly cadences (e.g. 3x / week) carry a
    /// per-*period* target of 3, but any single day is binary — one tap logs
    /// today — so the "log today" control fills toward 1, not the weekly budget.
    /// Only X-a-day cadences want a partial daily arc (2 of 3 today).
    private var target: Int {
        streak?.periodIsWeek == true ? 1 : max(1, streak?.target ?? 1)
    }

    /// Completions logged today, honoring any pending optimistic tap.
    private var todayCount: Int {
        optimisticToday ?? (streak?.todayCount ?? 0)
    }

    private var isSingleTarget: Bool { target == 1 }
    private var metToday: Bool { todayCount >= target }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spaceMD) {
                logButton
                // Single-target cadences undo by tapping the filled circle again;
                // count cadences only add per tap, so they get an explicit undo.
                if !isSingleTarget, todayCount > 0 {
                    Button(action: undoToday) {
                        Label("REMOVE ONE", systemImage: "minus.circle")
                            .font(Theme.labelFont(size: 10))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                streakStat
                if let recent = streak?.recent, !recent.isEmpty {
                    recentSection(recent)
                }
            }
            .padding(.top, Theme.spaceSM)
            .padding(.bottom, Theme.spaceLG)
        }
        .navigationTitle(current.title)
        .onChange(of: current.streak) { _, _ in
            // iPhone caught up — drop the optimistic override.
            optimisticToday = nil
        }
    }

    // MARK: - Log Today circle

    private var logButton: some View {
        Button(action: logToday) {
            ZStack {
                if metToday {
                    Circle().fill(Theme.ndAccent)
                } else {
                    Circle()
                        .strokeBorder(Theme.ndAccent.opacity(0.3), lineWidth: 3)
                    // Partial progress arc for count cadences (e.g. 2 of 3).
                    if todayCount > 0 {
                        Circle()
                            .trim(from: 0, to: min(1, Double(todayCount) / Double(target)))
                            .stroke(Theme.ndAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                VStack(spacing: 2) {
                    Image(systemName: metToday ? "checkmark" : "flame.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(metToday ? Color.black : Theme.ndAccent)
                    Text(centerLabel)
                        .font(Theme.labelFont(size: 9))
                        .tracking(0.8)
                        .foregroundStyle(metToday ? Color.black.opacity(0.7) : .secondary)
                }
            }
            .frame(width: 108, height: 108)
        }
        .buttonStyle(.plain)
    }

    private var centerLabel: String {
        if isSingleTarget {
            return metToday ? "LOGGED" : "LOG TODAY"
        }
        return "\(todayCount)/\(target) TODAY"
    }

    // MARK: - Streak stat

    private var streakStat: some View {
        let s = streak
        return VStack(spacing: 2) {
            Text("\(s?.currentStreak ?? 0)")
                .font(Theme.headingFont(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text((s?.periodIsWeek == true ? "WEEK" : "DAY") + " STREAK")
                .font(Theme.labelFont(size: 9))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            if let label = s?.cadenceLabel {
                Text(label.uppercased())
                    .font(Theme.labelFont(size: 8))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ndAccent.opacity(0.9))
                    .padding(.top, 1)
            }
        }
    }

    // MARK: - Recent entries

    private func recentSection(_ recent: [WatchStreakDay]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("RECENT")
                .font(Theme.labelFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            ForEach(Array(recent.enumerated()), id: \.offset) { _, day in
                HStack(spacing: Theme.spaceSM) {
                    Circle()
                        .fill(Theme.ndAccent)
                        .frame(width: 10, height: 10)
                    Text(Self.relativeLabel(for: day.date))
                        .font(Theme.bodyFont(size: 13))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, Theme.spaceSM)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
            }
        }
        .padding(.top, Theme.spaceXS)
    }

    // MARK: - Actions

    private func logToday() {
        let current = todayCount
        if isSingleTarget {
            optimisticToday = current > 0 ? 0 : 1
        } else {
            optimisticToday = current + 1
        }
        Theme.mediumHaptic()
        phone.send(.logStreakToday(filename: entry.filename)) { error in
            if error != nil { optimisticToday = nil } // revert on failure
        }
    }

    private func undoToday() {
        optimisticToday = max(0, todayCount - 1)
        Theme.lightHaptic()
        phone.send(.unlogStreakToday(filename: entry.filename)) { error in
            if error != nil { optimisticToday = nil }
        }
    }

    // MARK: - Formatting

    private static func relativeLabel(for date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        // Within the last week, show the weekday; otherwise a short date.
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
