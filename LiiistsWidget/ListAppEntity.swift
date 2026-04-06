import AppIntents
import Foundation

struct ListAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "List")
    static var defaultQuery = ListAppEntityQuery()

    var id: String // filename
    var title: String
    var itemCount: Int
    var type: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(itemCount) items")
    }
}

struct ListAppEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ListAppEntity] {
        let store = IntentListStore()
        let lists = store.loadAll()
        return identifiers.compactMap { id in
            guard let list = lists.first(where: { $0.filename == id }) else { return nil }
            return ListAppEntity(id: list.filename, title: list.title, itemCount: list.itemCount, type: list.type.rawValue)
        }
    }

    func suggestedEntities() async throws -> [ListAppEntity] {
        let store = IntentListStore()
        return store.loadAll().map { list in
            ListAppEntity(id: list.filename, title: list.title, itemCount: list.itemCount, type: list.type.rawValue)
        }
    }

    func defaultResult() async -> ListAppEntity? {
        try? await suggestedEntities().first
    }
}
