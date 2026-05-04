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
    let cadenceLabel: String
    let loggedToday: Bool
    let currentStreak: Int
    let filename: String
}

// MARK: - Provider

struct StreakWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: .now,
            listTitle: "Workouts",
            cadenceLabel: "Daily",
            loggedToday: false,
            currentStreak: 5,
            filename: ""
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
            return StreakWidgetEntry(
                date: .now,
                listTitle: "No list selected",
                cadenceLabel: "",
                loggedToday: false,
                currentStreak: 0,
                filename: ""
            )
        }

        let store = IntentListStore()
        guard let list = store.find(name: entity.title), list.type == .streak else {
            return StreakWidgetEntry(
                date: .now,
                listTitle: entity.title,
                cadenceLabel: "",
                loggedToday: false,
                currentStreak: 0,
                filename: entity.id
            )
        }

        let cadence = list.streakCadence ?? .daily
        let stats = StreakStats.compute(entries: list.streakEntries, cadence: cadence)

        return StreakWidgetEntry(
            date: .now,
            listTitle: list.title,
            cadenceLabel: cadence.displayLabel,
            loggedToday: list.isStreakDayLogged(Date()),
            currentStreak: stats.currentStreak,
            filename: list.filename
        )
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

        list.toggleStreakDay(Date())
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
            // Title + cadence
            Text(entry.listTitle.uppercased())
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .lineLimit(1)

            if !entry.cadenceLabel.isEmpty {
                Text(entry.cadenceLabel.uppercased())
                    .font(Theme.labelFont(size: 9))
                    .tracking(9 * 0.06)
                    .foregroundStyle(Theme.ndTextDisabled.resolve(for: colorScheme))
            }

            Spacer()

            // Tap-to-log circle
            HStack {
                Spacer()
                Button(intent: WidgetLogStreakIntent(filename: entry.filename)) {
                    ZStack {
                        Circle()
                            .fill(entry.loggedToday ? Theme.ndAccent : .clear)
                        Circle()
                            .strokeBorder(
                                entry.loggedToday
                                    ? Theme.ndAccent
                                    : Theme.ndBorderVisible.resolve(for: colorScheme),
                                lineWidth: entry.loggedToday ? 0 : 1.5
                            )
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .disabled(entry.filename.isEmpty)
                Spacer()
            }

            Spacer()

            // Current streak
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.currentStreak > 0 ? Theme.ndAccent : Theme.ndTextDisabled.resolve(for: colorScheme))
                Text("\(entry.currentStreak)")
                    .font(Theme.monoFont(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                Text("DAY\(entry.currentStreak == 1 ? "" : "S")")
                    .font(Theme.labelFont(size: 9))
                    .tracking(9 * 0.06)
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .description("Log a streak with a tap")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
