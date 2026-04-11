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
    let habits: [(name: String, loggedToday: Bool, currentStreak: Int)]
    let filename: String
}

// MARK: - Provider

struct StreakWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(date: .now, listTitle: "Habits", habits: [
            ("Workouts", true, 5),
            ("Meditation", false, 12),
            ("Reading", true, 3),
        ], filename: "")
    }

    func snapshot(for configuration: StreakWidgetIntent, in context: Context) async -> StreakWidgetEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: StreakWidgetIntent, in context: Context) async -> Timeline<StreakWidgetEntry> {
        let entry = loadEntry(for: configuration)
        // Refresh at midnight so "today" updates, and every 30 min for logged state
        let nextMidnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let next30Min = Date().addingTimeInterval(30 * 60)
        let nextRefresh = min(nextMidnight, next30Min)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(for configuration: StreakWidgetIntent) -> StreakWidgetEntry {
        guard let entity = configuration.list else {
            return StreakWidgetEntry(date: .now, listTitle: "No list selected", habits: [], filename: "")
        }

        let store = IntentListStore()
        guard let list = store.find(name: entity.title), list.type == .streak else {
            return StreakWidgetEntry(date: .now, listTitle: entity.title, habits: [], filename: entity.id)
        }

        let habits: [(name: String, loggedToday: Bool, currentStreak: Int)] = list.streakSections.map { section in
            let stats = StreakStats.compute(for: section)
            return (name: section.name, loggedToday: section.isLoggedToday(), currentStreak: stats.currentStreak)
        }

        return StreakWidgetEntry(date: .now, listTitle: list.title, habits: habits, filename: list.filename)
    }
}

// MARK: - Widget Log Intent (interactive button)

struct WidgetLogStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Streak from Widget"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Filename")
    var filename: String

    @Parameter(title: "Streak Name")
    var streakName: String

    init() {
        self.filename = ""
        self.streakName = ""
    }

    init(filename: String, streakName: String) {
        self.filename = filename
        self.streakName = streakName
    }

    func perform() async throws -> some IntentResult {
        let store = IntentListStore()
        let allLists = store.loadAll()
        guard var list = allLists.first(where: { $0.filename == filename }),
              list.type == .streak else {
            return .result()
        }

        guard let idx = list.streakSections.firstIndex(where: { $0.name == streakName }) else {
            return .result()
        }

        list.streakSections[idx].toggleToday()
        store.save(list)

        return .result()
    }
}

// MARK: - View

struct StreakWidgetView: View {
    let entry: StreakWidgetEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            Text(entry.listTitle.uppercased())
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .lineLimit(1)

            Spacer().frame(height: 2)

            if entry.habits.isEmpty {
                Text("No streaks yet")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.ndTextDisabled.resolve(for: colorScheme))
            } else {
                let maxHabits = family == .systemSmall ? 3 : 5
                ForEach(Array(entry.habits.prefix(maxHabits).enumerated()), id: \.offset) { _, habit in
                    Button(intent: WidgetLogStreakIntent(
                        filename: entry.filename,
                        streakName: habit.name
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: habit.loggedToday ? "circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(
                                    habit.loggedToday
                                        ? Theme.ndSuccess
                                        : Theme.ndTextSecondary.resolve(for: colorScheme)
                                )

                            Text(habit.name)
                                .font(Theme.bodyFont(size: family == .systemSmall ? 13 : 14))
                                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                                .lineLimit(1)

                            Spacer()

                            if habit.currentStreak > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.ndAccent)
                                    Text("\(habit.currentStreak)")
                                        .font(Theme.monoFont(size: 12))
                                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }

                if entry.habits.count > maxHabits {
                    Text("+\(entry.habits.count - maxHabits) more")
                        .font(Theme.labelFont(size: 10))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "liiists://list/\(entry.filename)"))
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
        .description("Log streaks with a tap")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
