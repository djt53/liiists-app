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
        let itemListType: ItemList.ListType
        switch listType {
        case .checklist: itemListType = .checklist
        case .streak: itemListType = .streak
        case .list: itemListType = .list
        }

        let list = ItemList(
            filename: filename,
            title: name,
            type: itemListType,
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
                "Add an item to a list in \(.applicationName)",
                "Add to a list in \(.applicationName)",
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

// MARK: - Log Streak Intent

struct LogStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Streak"
    static var description: IntentDescription = "Log today's entry for a streak list"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "List Name")
    var listName: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = IntentListStore()
        guard var list = store.find(name: listName), list.type == .streak else {
            throw IntentError.listNotFound(listName)
        }

        list.addStreakEntry(Date())
        store.save(list)

        return .result(value: "Logged \(list.title)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$listName)")
    }
}

// MARK: - Intent List Type

enum IntentListType: String, AppEnum {
    case list
    case checklist
    case streak

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "List Type"
    static var caseDisplayRepresentations: [IntentListType: DisplayRepresentation] = [
        .list: "List",
        .checklist: "Checklist",
        .streak: "Streak",
    ]
}

