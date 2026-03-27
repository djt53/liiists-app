import Foundation
import SwiftUI

/// Manages reading and writing ItemList markdown files from a directory.
@MainActor
final class ListStore: ObservableObject {
    @Published var lists: [ItemList] = []
    @Published var isLoaded = false

    private let fileManager = FileManager.default
    private var listsDirectory: URL

    init() {
        // Default to Documents/liiists — will move to iCloud container later
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.listsDirectory = docs.appendingPathComponent("liiists", isDirectory: true)
        ensureDirectory()
        loadAll()
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
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return MarkdownParser.parse(content: content, filename: url.lastPathComponent)
            }
            .sorted { ($0.title) < ($1.title) }

        isLoaded = true
    }

    func create(title: String, type: ItemList.ListType = .list) -> ItemList {
        let filename = ItemList.filenameFromTitle(title)
        var list = ItemList(
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
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func update(_ list: ItemList) {
        save(list)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
    }

    func delete(_ list: ItemList) {
        let url = listsDirectory.appendingPathComponent(list.filename)
        try? fileManager.removeItem(at: url)
        lists.removeAll { $0.id == list.id }
    }

    // MARK: - Private

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: listsDirectory.path) {
            try? fileManager.createDirectory(at: listsDirectory, withIntermediateDirectories: true)
        }
    }
}
