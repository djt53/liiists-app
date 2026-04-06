import AppIntents
import Foundation

// MARK: - Add Item Intent

struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Item to List"
    static var description: IntentDescription = "Add an item to one of your liiists"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "List Name")
    var listName: String

    @Parameter(title: "Item")
    var itemText: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = IntentListStore()
        guard var list = store.find(name: listName) else {
            throw IntentError.listNotFound(listName)
        }

        list.items.insert(ListItem(text: itemText), at: 0)
        store.save(list)

        return .result(value: "Added \"\(itemText)\" to \(list.title)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$itemText) to \(\.$listName)")
    }
}

// MARK: - Create List Intent

struct CreateListIntent: AppIntent {
    static var title: LocalizedStringResource = "Create List"
    static var description: IntentDescription = "Create a new liiists list"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Type", default: .list)
    var listType: IntentListType

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = IntentListStore()

        let filename = ItemList.filenameFromTitle(name)
        let list = ItemList(
            filename: filename,
            title: name,
            type: listType == .checklist ? .checklist : .list,
            createdDate: Date(),
            items: []
        )
        store.save(list)

        return .result(value: "Created list: \(name)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$listType) called \(\.$name)")
    }
}

// MARK: - Show Lists Intent

struct ShowListsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show My Lists"
    static var description: IntentDescription = "Show all your liiists"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = IntentListStore()
        let lists = store.loadAll()

        if lists.isEmpty {
            return .result(value: "You don't have any lists yet.")
        }

        let summary = lists.map { list in
            if list.type == .checklist && list.itemCount > 0 {
                return "\(list.title) (\(list.checkedCount)/\(list.itemCount))"
            } else {
                return "\(list.title) (\(list.itemCount) items)"
            }
        }.joined(separator: ", ")

        return .result(value: summary)
    }
}

// MARK: - Shortcuts Provider

struct LiiistsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add \(\.$itemText) to a list in \(.applicationName)",
            ],
            shortTitle: "Add Item",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ShowListsIntent(),
            phrases: [
                "Show my lists in \(.applicationName)",
                "What lists do I have in \(.applicationName)",
            ],
            shortTitle: "Show Lists",
            systemImageName: "list.bullet"
        )
    }
}

// MARK: - Intent List Type

enum IntentListType: String, AppEnum {
    case list
    case checklist

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "List Type"
    static var caseDisplayRepresentations: [IntentListType: DisplayRepresentation] = [
        .list: "List",
        .checklist: "Checklist",
    ]
}

// MARK: - Intent Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case listNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .listNotFound(let name):
            "List not found: \(name)"
        }
    }
}

// MARK: - Intent List Store (lightweight, no @MainActor)

/// A stripped-down list store for App Intents (runs outside the main app process).
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

        // Exact slug match
        let slug = ItemList.filenameFromTitle(name)
        if let match = lists.first(where: { $0.filename == slug }) {
            return match
        }

        // Title match (case-insensitive)
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
