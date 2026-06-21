import Foundation
import Combine

/// Holds the App Group catalog in memory for the watch UI to observe.
/// Reloaded on appear + whenever the iPhone pushes a `catalogUpdated`
/// nudge over WatchConnectivity.
@MainActor
final class WatchCatalogStore: ObservableObject {
    static let shared = WatchCatalogStore()

    @Published private(set) var entries: [WatchCatalogEntry] = []

    private init() {
        reload()
    }

    func reload() {
        entries = WatchCatalog.read()
    }

    func entry(filename: String) -> WatchCatalogEntry? {
        entries.first { $0.filename == filename }
    }

    var pinnedEntry: WatchCatalogEntry? {
        guard let pinned = WatchCatalog.pinnedFilename else { return nil }
        return entry(filename: pinned)
    }
}
