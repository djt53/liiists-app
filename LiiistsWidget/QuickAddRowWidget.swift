import SwiftUI
import WidgetKit

// MARK: - Entry

struct QuickAddRowEntry: TimelineEntry {
    let date: Date
    let recentLists: [(title: String, filename: String, isChecklist: Bool)]
}

// MARK: - Provider

struct QuickAddRowProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddRowEntry {
        QuickAddRowEntry(date: .now, recentLists: [
            ("Groceries", "groceries.md", false),
            ("Books", "books.md", true),
            ("Movies", "movies.md", true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddRowEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddRowEntry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func loadEntry() -> QuickAddRowEntry {
        let fm = FileManager.default
        let dir = SharedContainer.listsDirectory

        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return QuickAddRowEntry(date: .now, recentLists: [])
        }

        // Sort by modification date, most recent first
        let mdFiles = urls
            .filter { $0.pathExtension == "md" }
            .sorted { (a, b) -> Bool in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB
            }
            .prefix(3)

        let recentLists: [(title: String, filename: String, isChecklist: Bool)] = mdFiles.compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let list = MarkdownParser.parse(content: content, filename: url.lastPathComponent)
            return (title: list.title, filename: list.filename, isChecklist: list.type == .checklist)
        }

        return QuickAddRowEntry(date: .now, recentLists: recentLists)
    }
}

// MARK: - View

struct QuickAddRowWidgetView: View {
    let entry: QuickAddRowEntry
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                if index < entry.recentLists.count {
                    let list = entry.recentLists[index]
                    Link(destination: URL(string: "liiists://add/\(list.filename)")!) {
                        quickAddButton(
                            icon: list.isChecklist ? "checklist" : "list.bullet",
                            label: list.title
                        )
                    }
                } else {
                    placeholderButton
                }
            }
            Link(destination: URL(string: "liiists://new")!) {
                quickAddButton(icon: "plus", label: "NEW LIST")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickAddButton(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
            Text(label.uppercased())
                .font(Theme.labelFont(size: 9))
                .tracking(9 * 0.08)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var placeholderButton: some View {
        VStack {}
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .background(Theme.ndSurface.resolve(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

// MARK: - Widget

struct QuickAddRowWidget: Widget {
    let kind = "QuickAddRowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddRowProvider()) { entry in
            QuickAddRowWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.ndBlack.resolve(for: .dark)
                }
        }
        .configurationDisplayName("Quick Add Row")
        .description("Quick-add to recent lists or create a new one")
        .supportedFamilies([.systemMedium])
    }
}
