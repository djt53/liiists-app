import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Intent

struct QuickAddIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Quick Add"
    static var description: IntentDescription = "Choose which list to add items to"

    @Parameter(title: "List")
    var list: ListAppEntity?
}

// MARK: - Entry

struct QuickAddEntry: TimelineEntry {
    let date: Date
    let listTitle: String
    let filename: String
}

// MARK: - Provider

struct QuickAddProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now, listTitle: "Groceries", filename: "")
    }

    func snapshot(for configuration: QuickAddIntent, in context: Context) async -> QuickAddEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: QuickAddIntent, in context: Context) async -> Timeline<QuickAddEntry> {
        let entry = loadEntry(for: configuration)
        return Timeline(entries: [entry], policy: .never)
    }

    private func loadEntry(for configuration: QuickAddIntent) -> QuickAddEntry {
        guard let entity = configuration.list else {
            return QuickAddEntry(date: .now, listTitle: "Select a list", filename: "")
        }
        return QuickAddEntry(date: .now, listTitle: entity.title, filename: entity.id)
    }
}

// MARK: - View

struct QuickAddWidgetView: View {
    let entry: QuickAddEntry
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "plus.circle")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

            Text(entry.listTitle.uppercased())
                .font(Theme.labelFont(size: 11))
                .tracking(11 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .lineLimit(1)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .widgetURL(URL(string: "liiists://add/\(entry.filename)"))
    }
}

// MARK: - Widget

struct QuickAddWidget: Widget {
    let kind = "QuickAddWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuickAddIntent.self,
            provider: QuickAddProvider()
        ) { entry in
            QuickAddWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.ndBlack.resolve(for: .dark)
                }
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to add an item to a list")
        .supportedFamilies([.systemSmall])
    }
}
