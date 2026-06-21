import SwiftUI
import WidgetKit

/// Pinned-list status — rectangular/corner families. Shows the pinned
/// list's title + a glanceable value (item count for regular/checklist,
/// most recent entry for log lists). Pinned filename lives in
/// App Group UserDefaults, set from the iPhone's SettingsSheet.
struct PinnedListComplication: Widget {
    let kind = "PinnedListComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PinnedListView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(deepLink(for: entry))
        }
        .configurationDisplayName("Pinned List")
        .description("Glanceable status from one of your lists.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }

    private func deepLink(for entry: Entry) -> URL? {
        guard let filename = entry.entry?.filename,
              let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return URL(string: "liiists://home")
        }
        return URL(string: "liiists://list/\(encoded)")
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date(), entry: nil)
        }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(currentEntry())
        }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [currentEntry()], policy: .never))
        }

        private func currentEntry() -> Entry {
            Entry(date: Date(), entry: WatchCatalogStore.pinnedSnapshot())
        }
    }

    struct Entry: TimelineEntry {
        let date: Date
        let entry: WatchCatalogEntry?
    }
}

/// Tiny adapter so the widget extension can read pinned snapshot without
/// dragging the @MainActor WatchCatalogStore class in.
private enum WatchCatalogStore {
    static func pinnedSnapshot() -> WatchCatalogEntry? {
        guard let filename = WatchCatalog.pinnedFilename else { return nil }
        return WatchCatalog.read().first { $0.filename == filename }
    }
}

private struct PinnedListView: View {
    let entry: PinnedListComplication.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let listEntry = entry.entry {
            switch family {
            case .accessoryRectangular:
                rectangular(listEntry)
            case .accessoryCorner:
                corner(listEntry)
            case .accessoryInline:
                inline(listEntry)
            default:
                rectangular(listEntry)
            }
        } else {
            empty
        }
    }

    private func rectangular(_ entry: WatchCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(headline(for: entry))
                .font(.system(size: 16, weight: .bold))
                .lineLimit(2)
            Text(subhead(for: entry))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func corner(_ entry: WatchCatalogEntry) -> some View {
        Image(systemName: icon(for: entry.type))
            .foregroundStyle(Theme.ndAccent)
            .widgetLabel(headline(for: entry))
    }

    private func inline(_ entry: WatchCatalogEntry) -> some View {
        Label("\(entry.title) — \(subhead(for: entry))", systemImage: icon(for: entry.type))
    }

    private var empty: some View {
        VStack(spacing: 2) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .foregroundStyle(.secondary)
            Text("PIN A LIST")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Per-type rendering

    private func icon(for type: String) -> String {
        switch type {
        case "checklist": return "checklist"
        case "log": return "clock"
        case "streak": return "flame"
        default: return "list.bullet"
        }
    }

    private func headline(for entry: WatchCatalogEntry) -> String {
        switch entry.type {
        case "checklist":
            return "\(entry.checkedCount)/\(entry.itemCount)"
        case "log":
            return entry.items.first?.text ?? "No entries yet"
        default:
            return "\(entry.itemCount)"
        }
    }

    private func subhead(for entry: WatchCatalogEntry) -> String {
        switch entry.type {
        case "checklist": return "checked"
        case "log": return "latest"
        default: return entry.itemCount == 1 ? "item" : "items"
        }
    }
}
