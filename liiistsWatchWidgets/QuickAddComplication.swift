import SwiftUI
import WidgetKit

/// The marquee complication — a button. Tap deep-links into the watch
/// app's dictation flow. No data; refresh is meaningless because the
/// content never changes.
struct QuickAddComplication: Widget {
    let kind = "QuickAddComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            QuickAddView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "liiists://dictate"))
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to dictate a new entry.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date()))
        }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: Date())], policy: .never))
        }
    }

    struct Entry: TimelineEntry {
        let date: Date
    }
}

private struct QuickAddView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle().strokeBorder(Theme.ndAccent, lineWidth: 1.5)
                Image(systemName: "mic.fill")
                    .foregroundStyle(Theme.ndAccent)
            }
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.ndAccent)
                .widgetLabel("liiists")
        case .accessoryInline:
            Label("Dictate to liiists", systemImage: "mic.fill")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ndAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("liiists")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("DICTATE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                }
            }
        default:
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.ndAccent)
        }
    }
}
