import Foundation

/// A lightweight projection of an ItemList for the watch's App Group cache.
/// Watch reads these to power browse + complications without needing
/// access to iCloud Drive (which isn't reachable from watchOS).
struct WatchCatalogEntry: Codable, Identifiable, Hashable {
    var id: String { filename }
    let filename: String
    let title: String
    let type: String              // raw value of ItemList.ListType
    let itemCount: Int
    let checkedCount: Int
    let items: [WatchCatalogItem]
    let modifiedDate: Date?
}

struct WatchCatalogItem: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let isChecked: Bool
    let timestamp: Date?           // populated only for log entries
}

/// Shared App Group catalog. iPhone calls `writeCatalog` after every list
/// mutation; watch calls `read()` from views + complication
/// TimelineProviders. The catalog is the durable contract between the
/// two devices; WatchSyncService.notifyCatalogUpdated() is just a
/// wake-up nudge.
enum WatchCatalog {
    static let appGroupID = "group.com.davidtingle.liiists"
    static let catalogKey = "watch_catalog_v1"
    static let pinnedListKey = "watch_pinned_list_filename"
    static let maxEntries = 50
    static let maxItemsPerEntry = 50

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func read() -> [WatchCatalogEntry] {
        guard let defaults, let data = defaults.data(forKey: catalogKey) else { return [] }
        return (try? JSONDecoder().decode([WatchCatalogEntry].self, from: data)) ?? []
    }

    static func writeCatalog(_ entries: [WatchCatalogEntry]) {
        guard let defaults, let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: catalogKey)
    }

    static var pinnedFilename: String? {
        get { defaults?.string(forKey: pinnedListKey) }
        set {
            guard let defaults else { return }
            if let newValue {
                defaults.set(newValue, forKey: pinnedListKey)
            } else {
                defaults.removeObject(forKey: pinnedListKey)
            }
        }
    }
}
