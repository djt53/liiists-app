import Foundation
import os.log
import SwiftUI
import WidgetKit

private let coldOpenLog = Logger(subsystem: "com.davidtingle.liiists", category: "cold_open")

/// Manages reading and writing ItemList markdown files from a directory.
/// Monitors iCloud Drive for changes from other devices or Files.app.
@MainActor
final class ListStore: ObservableObject {
    @Published var lists: [ItemList] = []
    @Published var isLoaded = false

    /// Optional hook called after every successful save. Used by PublishStore
    /// to auto-republish lists that have been published to the social feed
    /// (decision 006). Set from liiistsApp at startup.
    var republishHook: ((ItemList) -> Void)?

    private let fileManager = FileManager.default
    private var listsDirectory: URL
    private var metadataQuery: NSMetadataQuery?
    private var identityObserver: NSObjectProtocol?

    init() {
        // Cold-open hot path: do *no* blocking work here. The real
        // `listsDirectory` resolution calls `url(forUbiquityContainerIdentifier:)`
        // which Apple explicitly warns must not run on the main thread —
        // first launches and weak-network conditions can stall it for seconds,
        // freezing the launch screen. Seed with the App Group fallback so
        // SwiftUI can render the first frame (HomeView's ProgressView),
        // then resolve the real directory in `bootstrap()` below.
        self.listsDirectory = SharedContainer.fallbackDirectory
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    /// Resolves the real lists directory off the main thread, runs migrations,
    /// then hops back to the main actor to swap state, load lists, and start
    /// the iCloud metadata query. Invoked from `init()` and from
    /// `handleiCloudIdentityChange()` when the user signs in/out of iCloud.
    private func bootstrap() async {
        let started = Date()
        let resolvedDir = await Task.detached(priority: .userInitiated) {
            SharedContainer.migrateIfNeeded()
            SharedContainer.migrateToiCloudIfNeeded()
            return SharedContainer.listsDirectory
        }.value
        let bootstrapMs = Int(Date().timeIntervalSince(started) * 1000)

        self.listsDirectory = resolvedDir
        SharedContainer.ensureDirectory()
        let loadStart = Date()
        loadAll()
        let loadMs = Int(Date().timeIntervalSince(loadStart) * 1000)
        startMonitoring()
        coldOpenLog.info("bootstrap \(bootstrapMs, privacy: .public)ms, loadAll \(loadMs, privacy: .public)ms")
    }

    deinit {
        metadataQuery?.stop()
        if let observer = identityObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    func loadAll() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: listsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            isLoaded = true
            return
        }

        // Preserve existing ItemList UUIDs across reloads. iCloud's
        // NSMetadataQuery fires `loadAll()` on every local write, and parsing
        // generates fresh UUIDs by default — but NavigationStack identity is
        // keyed on `id`, so regenerating would invalidate any active path
        // entry (blank screen after create/rename). The rename path mutates
        // `lists[idx]` with the new filename before this runs, so mapping by
        // current filename carries the id forward across renames too.
        var existingIdByFilename: [String: UUID] = [:]
        for list in lists {
            existingIdByFilename[list.filename] = list.id
        }

        lists = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> ItemList? in
                var content: String?
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordURL in
                    content = try? String(contentsOf: coordURL, encoding: .utf8)
                }
                guard let content else { return nil }
                let filename = url.lastPathComponent
                var parsed = MarkdownParser.parse(
                    content: content,
                    filename: filename,
                    existingId: existingIdByFilename[filename]
                )
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                parsed.modifiedDate = values?.contentModificationDate
                return parsed
            }
            .sorted { ($0.title) < ($1.title) }

        isLoaded = true
        syncWatchCatalog()
    }

    func create(
        title: String,
        type: ItemList.ListType = .list,
        cadence: StreakCadence? = nil
    ) -> ItemList {
        let filename = ItemList.filenameFromTitle(title)
        let list = ItemList(
            filename: filename,
            title: title,
            type: type,
            createdDate: Date(),
            items: [],
            streakCadence: type == .streak ? cadence : nil
        )
        save(list)
        lists.append(list)
        lists.sort { $0.title < $1.title }
        syncWatchCatalog()
        Analytics.listCreated(title: title, type: type.rawValue)
        return list
    }

    func save(_ list: ItemList) {
        let content = MarkdownParser.write(list)
        let url = listsDirectory.appendingPathComponent(list.filename)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? content.write(to: coordURL, atomically: true, encoding: .utf8)
        }
        WidgetCenter.shared.reloadAllTimelines()
        republishHook?(list)
    }

    func rename(_ list: inout ItemList, to newTitle: String) {
        let oldTitle = list.title
        let oldFilename = list.filename
        let oldURL = listsDirectory.appendingPathComponent(list.filename)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: oldURL, options: .forDeleting, error: &error) { coordURL in
            try? fileManager.removeItem(at: coordURL)
        }

        list.title = newTitle
        list.filename = ItemList.filenameFromTitle(newTitle)

        save(list)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
        lists.sort { $0.title < $1.title }
        updateManualOrderForRename(oldFilename: oldFilename, newFilename: list.filename)
        syncWatchCatalog()
        Analytics.listRenamed(from: oldTitle, to: newTitle)
    }

    private func updateManualOrderForRename(oldFilename: String, newFilename: String) {
        guard oldFilename != newFilename else { return }
        let defaults = UserDefaults.standard
        let key = "home_manual_order"
        guard let raw = defaults.string(forKey: key), !raw.isEmpty else { return }
        var filenames = raw.split(separator: ",").map(String.init)
        guard let idx = filenames.firstIndex(of: oldFilename) else { return }
        filenames[idx] = newFilename
        defaults.set(filenames.joined(separator: ","), forKey: key)
    }

    func update(_ list: ItemList) {
        save(list)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
        syncWatchCatalog()
    }

    func delete(_ list: ItemList) {
        let url = listsDirectory.appendingPathComponent(list.filename)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { coordURL in
            try? fileManager.removeItem(at: coordURL)
        }
        lists.removeAll { $0.id == list.id }
        syncWatchCatalog()
        Analytics.listDeleted(title: list.title)
    }

    // MARK: - iCloud Monitoring

    private func startMonitoring() {
        guard SharedContainer.isiCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleMetadataQueryUpdate(query)
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleMetadataQueryUpdate(query)
        }

        query.start()
        self.metadataQuery = query

        // Watch for iCloud account changes
        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleiCloudIdentityChange()
        }
    }

    private nonisolated func handleMetadataQueryUpdate(_ query: NSMetadataQuery) {
        query.disableUpdates()

        // Trigger download for any not-yet-downloaded files
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded,
               let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        query.enableUpdates()

        Task { @MainActor [weak self] in
            self?.loadAll()
        }
    }

    private func handleiCloudIdentityChange() {
        metadataQuery?.stop()
        metadataQuery = nil
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    // MARK: - Watch catalog

    /// Projects `lists` into a lightweight catalog, writes it to the
    /// iPhone-local App Group, AND ships the same payload to the watch
    /// via WCSession.updateApplicationContext. App Groups don't span
    /// iPhone↔Watch, so the WC trip is what actually makes the catalog
    /// visible on the wrist.
    private func syncWatchCatalog() {
        let entries = lists
            .sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
            .prefix(WatchCatalog.maxEntries)
            .map { list -> WatchCatalogEntry in
                let items = list.items.prefix(WatchCatalog.maxItemsPerEntry).map {
                    WatchCatalogItem(
                        id: $0.id,
                        text: $0.text,
                        isChecked: $0.isChecked,
                        timestamp: $0.timestamp
                    )
                }
                return WatchCatalogEntry(
                    filename: list.filename,
                    title: list.title,
                    type: list.type.rawValue,
                    itemCount: list.itemCount,
                    checkedCount: list.checkedCount,
                    items: Array(items),
                    modifiedDate: list.modifiedDate
                )
            }
        WatchCatalog.writeCatalog(Array(entries))
        WatchSyncService.shared.notifyCatalogUpdated()
    }
}
