import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Intent

struct SingleListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select List"
    static var description: IntentDescription = "Choose which list to display"

    @Parameter(title: "List")
    var list: ListAppEntity?
}

// MARK: - Entry

struct SingleListEntry: TimelineEntry {
    let date: Date
    let listTitle: String
    let items: [(text: String, isChecked: Bool)]
    let isChecklist: Bool
    let filename: String
}

// MARK: - Provider

struct SingleListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleListEntry {
        SingleListEntry(date: .now, listTitle: "Books", items: [
            ("Project Hail Mary", false),
            ("Tomorrow, and Tomorrow", true),
            ("The Kaiju Preservation Society", false),
        ], isChecklist: true, filename: "")
    }

    func snapshot(for configuration: SingleListIntent, in context: Context) async -> SingleListEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: SingleListIntent, in context: Context) async -> Timeline<SingleListEntry> {
        let entry = loadEntry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func loadEntry(for configuration: SingleListIntent) -> SingleListEntry {
        guard let entity = configuration.list else {
            return SingleListEntry(date: .now, listTitle: "No list selected", items: [], isChecklist: false, filename: "")
        }

        let store = IntentListStore()
        if let list = store.find(name: entity.title) {
            let items = list.items.map { ($0.text, $0.isChecked) }
            return SingleListEntry(date: .now, listTitle: list.title, items: items, isChecklist: list.type == .checklist, filename: list.filename)
        }

        return SingleListEntry(date: .now, listTitle: entity.title, items: [], isChecklist: false, filename: entity.id)
    }
}

// MARK: - View

struct SingleListWidgetView: View {
    let entry: SingleListEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 6
        case .systemLarge: return 14
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title
            Text(entry.listTitle.uppercased())
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .lineLimit(1)

            Spacer().frame(height: 4)

            // Items
            let visibleItems = Array(entry.items.prefix(maxItems))
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    if entry.isChecklist {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(item.isChecked ? Theme.ndSuccess : Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                    Text(item.text)
                        .font(Theme.bodyFont(size: family == .systemSmall ? 13 : 14))
                        .foregroundStyle(
                            item.isChecked
                                ? Theme.ndTextDisabled.resolve(for: colorScheme)
                                : Theme.ndTextPrimary.resolve(for: colorScheme)
                        )
                        .lineLimit(1)
                }
            }

            if entry.items.count > maxItems {
                Text("+\(entry.items.count - maxItems) more")
                    .font(Theme.labelFont(size: 10))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "liiists://list/\(entry.filename)"))
    }
}

// MARK: - Widget

struct SingleListWidget: Widget {
    let kind = "SingleListWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SingleListIntent.self,
            provider: SingleListProvider()
        ) { entry in
            SingleListWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.ndBlack.resolve(for: .dark)
                }
        }
        .configurationDisplayName("List")
        .description("View items from a specific list")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
