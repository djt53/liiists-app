import Foundation
import SwiftUI

/// Manages reading and writing ItemList markdown files from a directory.
/// Monitors iCloud Drive for changes from other devices or Files.app.
@MainActor
final class ListStore: ObservableObject {
    @Published var lists: [ItemList] = []
    @Published var isLoaded = false

    private let fileManager = FileManager.default
    private var listsDirectory: URL
    private var metadataQuery: NSMetadataQuery?
    private var identityObserver: NSObjectProtocol?

    init() {
        self.listsDirectory = SharedContainer.listsDirectory
        SharedContainer.migrateIfNeeded()
        SharedContainer.migrateToiCloudIfNeeded()
        SharedContainer.ensureDirectory()
        loadAll()
        startMonitoring()
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
                return MarkdownParser.parse(content: content, filename: url.lastPathComponent)
            }
            .sorted { ($0.title) < ($1.title) }

        isLoaded = true
    }

    func create(title: String, type: ItemList.ListType = .list) -> ItemList {
        let filename = ItemList.filenameFromTitle(title)
        let list = ItemList(
            filename: filename,
            title: title,
            type: type,
            createdDate: Date(),
            items: []
        )
        save(list)
        lists.append(list)
        lists.sort { $0.title < $1.title }
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
    }

    func rename(_ list: inout ItemList, to newTitle: String) {
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
    }

    func update(_ list: ItemList) {
        save(list)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
    }

    func delete(_ list: ItemList) {
        let url = listsDirectory.appendingPathComponent(list.filename)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { coordURL in
            try? fileManager.removeItem(at: coordURL)
        }
        lists.removeAll { $0.id == list.id }
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
        self.listsDirectory = SharedContainer.listsDirectory
        SharedContainer.ensureDirectory()
        metadataQuery?.stop()
        if SharedContainer.isiCloudAvailable {
            startMonitoring()
        }
        loadAll()
    }
}
