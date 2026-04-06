import Foundation

/// A stripped-down list store for App Intents and Widgets (runs outside the main app process).
struct IntentListStore {
    private let fileManager = FileManager.default
    private let listsDirectory: URL

    init() {
        self.listsDirectory = SharedContainer.listsDirectory
        SharedContainer.ensureDirectory()
    }

    func loadAll() -> [ItemList] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: listsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> ItemList? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return MarkdownParser.parse(content: content, filename: url.lastPathComponent)
            }
            .sorted { $0.title < $1.title }
    }

    func find(name: String) -> ItemList? {
        let lists = loadAll()
        let nameLower = name.lowercased()

        let slug = ItemList.filenameFromTitle(name)
        if let match = lists.first(where: { $0.filename == slug }) {
            return match
        }

        return lists.first { $0.title.lowercased() == nameLower }
    }

    func save(_ list: ItemList) {
        let content = MarkdownParser.write(list)
        let url = listsDirectory.appendingPathComponent(list.filename)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? content.write(to: coordURL, atomically: true, encoding: .utf8)
        }
    }
}

/// Errors for App Intent operations.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case listNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .listNotFound(let name):
            "List not found: \(name)"
        }
    }
}
