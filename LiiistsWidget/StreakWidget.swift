import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Intent

struct StreakWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Streak List"
    static var description: IntentDescription = "Choose which streak list to display"

    @Parameter(title: "List")
    var list: ListAppEntity?
}

// MARK: - Entry

struct StreakWidgetEntry: TimelineEntry {
    let date: Date
    let listTitle: String
    let totalCount: Int
    let currentStreak: Int
    /// True for week-period cadences — drives the streak unit label.
    let isWeekly: Bool
    /// Completions required for a single day-dot to read as "met". For day-based
    /// cadences this is the cadence target (X/day); for weekly cadences it's 1,
    /// so the daily dots stay binary while the streak counts weeks.
    let dotTarget: Int
    let filename: String
    /// Completion counts for the last 7 calendar days, oldest first (last = today).
    let recentCounts: [Int]

    var todayCount: Int { recentCounts.last ?? 0 }
    var loggedToday: Bool { todayCount >= dotTarget }
}

// MARK: - Provider

struct StreakWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: .now,
            listTitle: "Workouts",
            totalCount: 12,
            currentStreak: 5,
            isWeekly: false,
            dotTarget: 1,
            filename: "",
            recentCounts: [1, 1, 0, 1, 1, 1, 0]
        )
    }

    func snapshot(for configuration: StreakWidgetIntent, in context: Context) async -> StreakWidgetEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: StreakWidgetIntent, in context: Context) async -> Timeline<StreakWidgetEntry> {
        let entry = loadEntry(for: configuration)
        let nextMidnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let next30Min = Date().addingTimeInterval(30 * 60)
        let nextRefresh = min(nextMidnight, next30Min)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(for configuration: StreakWidgetIntent) -> StreakWidgetEntry {
        guard let entity = configuration.list else {
            return Self.emptyEntry(title: "No list selected", filename: "")
        }

        let store = IntentListStore()
        guard let list = store.find(name: entity.title), list.type == .streak else {
            return Self.emptyEntry(title: entity.title, filename: entity.id)
        }

        let cadence = list.streakCadence ?? .daily
        let stats = StreakStats.compute(
            entries: list.streakEntries.filter(\.filled).map(\.date),
            cadence: cadence
        )
        return StreakWidgetEntry(
            date: .now,
            listTitle: list.title,
            totalCount: list.streakLoggedCount,
            currentStreak: stats.currentStreak,
            isWeekly: cadence.period == .week,
            dotTarget: cadence.period == .day ? cadence.target : 1,
            filename: list.filename,
            recentCounts: Self.recentCounts(for: list, days: 7)
        )
    }

    private static func emptyEntry(title: String, filename: String) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: .now,
            listTitle: title,
            totalCount: 0,
            currentStreak: 0,
            isWeekly: false,
            dotTarget: 1,
            filename: filename,
            recentCounts: Array(repeating: 0, count: 7)
        )
    }

    /// Completion counts for the last `days` calendar days, oldest first (last = today).
    private static func recentCounts(for list: ItemList, days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var perDay: [Date: Int] = [:]
        for entry in list.streakEntries where entry.filled {
            perDay[cal.startOfDay(for: entry.date), default: 0] += 1
        }
        return (0..<days).reversed().map { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return perDay[day] ?? 0
        }
    }
}

// MARK: - Widget Log Intent (interactive button)

struct WidgetLogStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Streak from Widget"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Filename")
    var filename: String

    init() {
        self.filename = ""
    }

    init(filename: String) {
        self.filename = filename
    }

    func perform() async throws -> some IntentResult {
        let store = IntentListStore()
        let allLists = store.loadAll()
        guard var list = allLists.first(where: { $0.filename == filename }),
              list.type == .streak else {
            return .result()
        }

        list.addStreakEntry(Date())
        store.save(list)

        return .result()
    }
}

// MARK: - View

struct StreakWidgetView: View {
    let entry: StreakWidgetEntry
    @Environment(\.widgetFamily) var family
    // The widget background is always forced-dark (see containerBackground), so
    // resolve every token for dark — not the device appearance, which would
    // otherwise render white fills as black-on-black in light mode.
    private let colorScheme: ColorScheme = .dark

    private var titleLabel: some View {
        Text(entry.listTitle.uppercased())
            .font(Theme.labelFont(size: 11))
            .tracking(11 * 0.08)
            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            .lineLimit(1)
    }

    /// Current streak — the headline glance value, unit-aware (day vs week).
    private var streakLabel: some View {
        HStack(spacing: 4) {
            Text("\(entry.currentStreak)")
                .font(Theme.monoFont(size: 14, weight: .bold))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
            Text(entry.isWeekly ? "WK STREAK" : "DAY STREAK")
                .font(Theme.labelFont(size: 9))
                .tracking(9 * 0.06)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
    }

    /// Interactive tap-to-log circle. Solid green once today's target is met;
    /// for X/day cadences an in-progress day shows a partial arc.
    private func tapCircle(size: CGFloat) -> some View {
        let count = entry.todayCount
        let target = entry.dotTarget
        let met = count >= target
        let fraction = target > 0 ? min(1, Double(count) / Double(target)) : 0
        return Button(intent: WidgetLogStreakIntent(filename: entry.filename)) {
            ZStack {
                if met {
                    Circle().fill(Theme.ndSuccess)
                } else {
                    Circle().strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1.5)
                    if target > 1 {
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(Theme.ndSuccess, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(size * 0.07)
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(entry.filename.isEmpty)
    }

    /// A read-only history dot — solid white when that day met target, a partial
    /// arc for count-based cadences in progress, else an empty ring.
    private func historyDot(count: Int, size: CGFloat) -> some View {
        let target = entry.dotTarget
        let met = count >= target
        let fraction = target > 0 ? min(1, Double(count) / Double(target)) : 0
        return ZStack {
            if met {
                Circle().fill(Theme.ndTextDisplay.resolve(for: colorScheme))
            } else {
                Circle().strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                if target > 1 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Theme.ndTextDisplay.resolve(for: colorScheme),
                                style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.07)
                }
            }
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "liiists://list/\(entry.filename)"))
    }

    // MARK: Small — single tap-to-log circle

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLabel
            Spacer()
            HStack {
                Spacer()
                tapCircle(size: 56)
                Spacer()
            }
            Spacer()
            streakLabel
        }
    }

    // MARK: Medium — last-7-days timeline, today is the tap target

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                titleLabel
                Spacer()
                streakLabel
            }

            Spacer()

            // Newest-first to match the in-app grid: today (interactive) leads on
            // the left, history extends to the right into the past.
            HStack(spacing: 12) {
                ForEach(Array(entry.recentCounts.reversed().enumerated()), id: \.offset) { i, count in
                    if i == 0 {
                        tapCircle(size: 34)
                    } else {
                        historyDot(count: count, size: 30)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }
}

// MARK: - Widget

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: StreakWidgetIntent.self,
            provider: StreakWidgetProvider()
        ) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.ndBlack.resolve(for: .dark)
                }
        }
        .configurationDisplayName("Streak Check-In")
        .description("Log a streak entry with a tap")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
