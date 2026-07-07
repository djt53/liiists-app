import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Entry

struct AllListsEntry: TimelineEntry {
    let date: Date
    let lists: [(title: String, itemCount: Int, checkedCount: Int, isChecklist: Bool, isStreak: Bool, streakCount: Int, filename: String)]
}

// MARK: - Provider

struct AllListsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllListsEntry {
        AllListsEntry(date: .now, lists: [
            ("Books", 5, 2, true, false, 0, "books.md"),
            ("Groceries", 8, 0, false, false, 0, "groceries.md"),
            ("Workouts", 0, 0, false, true, 9, "workouts.md"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (AllListsEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllListsEntry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func loadEntry() -> AllListsEntry {
        let store = IntentListStore()
        let lists = store.loadAll().map { list in
            (title: list.title,
             itemCount: list.itemCount,
             checkedCount: list.checkedCount,
             isChecklist: list.type == .checklist,
             isStreak: list.type == .streak,
             streakCount: list.streakEntries.count,
             filename: list.filename)
        }
        return AllListsEntry(date: .now, lists: lists)
    }
}

// MARK: - View

struct AllListsWidgetView: View {
    let entry: AllListsEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private var maxLists: Int {
        switch family {
        case .systemMedium: return 5
        case .systemLarge: return 12
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LIIISTS")
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))

            Spacer().frame(height: 4)

            let visibleLists = Array(entry.lists.prefix(maxLists))
            ForEach(Array(visibleLists.enumerated()), id: \.offset) { _, list in
                Link(destination: URL(string: "liiists://list/\(list.filename)")!) {
                    HStack(spacing: 6) {
                        Image(systemName: list.isStreak ? "flame" : (list.isChecklist ? "checklist" : "list.bullet"))
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(list.isStreak ? Theme.ndAccent : Theme.ndTextSecondary.resolve(for: colorScheme))
                            .frame(width: 16)
                        Text(list.title)
                            .font(Theme.bodyFont(size: 14))
                            .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                            .lineLimit(1)
                        Spacer()
                        if list.isStreak && list.streakCount > 0 {
                            Text("\(list.streakCount)")
                                .font(Theme.labelFont(size: 10))
                                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        } else if list.isChecklist && list.itemCount > 0 {
                            Text("\(list.checkedCount)/\(list.itemCount)")
                                .font(Theme.labelFont(size: 10))
                                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        } else if list.itemCount > 0 {
                            Text("\(list.itemCount)")
                                .font(Theme.labelFont(size: 10))
                                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        }
                    }
                    .frame(minHeight: 22)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct AllListsWidget: Widget {
    let kind = "AllListsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AllListsProvider()) { entry in
            AllListsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.ndBlack.resolve(for: .dark)
                }
        }
        .configurationDisplayName("All Lists")
        .description("Browse your lists")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
