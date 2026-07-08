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
    /// Logged-state of the last 7 calendar days, oldest first (last element = today).
    let recentLogged: [Bool]
}

// MARK: - Provider

struct StreakWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: .now,
            listTitle: "Workouts",
            loggedToday: false,
            totalCount: 12,
            filename: "",
            recentLogged: [true, true, false, true, true, true, false]
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
                filename: "",
                recentLogged: Array(repeating: false, count: 7)
            )
        }

        let store = IntentListStore()
        guard let list = store.find(name: entity.title), list.type == .streak else {
            return StreakWidgetEntry(
                date: .now,
                listTitle: entity.title,
                loggedToday: false,
                totalCount: 0,
                filename: entity.id,
                recentLogged: Array(repeating: false, count: 7)
            )
        }

        return StreakWidgetEntry(
            date: .now,
            listTitle: list.title,
            loggedToday: list.isStreakDayLogged(Date()),
            totalCount: list.streakLoggedCount,
            filename: list.filename,
            recentLogged: Self.recentLogged(for: list, days: 7)
        )
    }

    /// Logged-state of the last `days` calendar days, oldest first (last = today).
    private static func recentLogged(for list: ItemList, days: Int) -> [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return false }
            return list.isStreakDayLogged(day)
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

    private var countLabel: some View {
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

    /// Interactive tap-to-log circle — green when today is already logged.
    private func tapCircle(size: CGFloat) -> some View {
        Button(intent: WidgetLogStreakIntent(filename: entry.filename)) {
            ZStack {
                Circle()
                    .fill(entry.loggedToday ? Theme.ndSuccess : .clear)
                Circle()
                    .strokeBorder(
                        entry.loggedToday
                            ? Theme.ndSuccess
                            : Theme.ndBorderVisible.resolve(for: colorScheme),
                        lineWidth: entry.loggedToday ? 0 : 1.5
                    )
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(entry.filename.isEmpty)
    }

    /// A read-only history dot — white when that day was logged, else an empty ring.
    private func historyDot(logged: Bool, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(logged ? Theme.ndTextDisplay.resolve(for: colorScheme) : .clear)
            Circle()
                .strokeBorder(
                    logged ? .clear : Theme.ndBorderVisible.resolve(for: colorScheme),
                    lineWidth: logged ? 0 : 1
                )
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
            countLabel
        }
    }

    // MARK: Medium — last-7-days timeline, today is the tap target

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                titleLabel
                Spacer()
                countLabel
            }

            Spacer()

            // Newest-first to match the in-app grid: today (interactive) leads on
            // the left, history extends to the right into the past.
            HStack(spacing: 12) {
                ForEach(Array(entry.recentLogged.reversed().enumerated()), id: \.offset) { i, logged in
                    if i == 0 {
                        tapCircle(size: 34)
                    } else {
                        historyDot(logged: logged, size: 30)
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
