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
    let loggedToday: Bool
    let totalCount: Int
    let filename: String
}

// MARK: - Provider

struct StreakWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: .now,
            listTitle: "Workouts",
            loggedToday: false,
            totalCount: 12,
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
                loggedToday: false,
                totalCount: 0,
                filename: ""
            )
        }

        let store = IntentListStore()
        guard let list = store.find(name: entity.title), list.type == .streak else {
            return StreakWidgetEntry(
                date: .now,
                listTitle: entity.title,
                loggedToday: false,
                totalCount: 0,
                filename: entity.id
            )
        }

        return StreakWidgetEntry(
            date: .now,
            listTitle: list.title,
            loggedToday: list.isStreakDayLogged(Date()),
            totalCount: list.streakEntries.count,
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

        list.addStreakEntry(Date())
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

            // Total completions
            HStack(spacing: 4) {
                Text("\(entry.totalCount)")
                    .font(Theme.monoFont(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                Text("LOGGED")
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
        .description("Log a streak entry with a tap")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
