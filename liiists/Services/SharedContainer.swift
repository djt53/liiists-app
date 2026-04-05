import Foundation

/// Shared container paths for App Group access.
/// Used by the main app, App Intents, and the Share Extension.
enum SharedContainer {
    static let appGroupID = "group.com.davidtingle.liiists"

    /// The shared lists directory inside the App Group container.
    /// Falls back to Documents/liiists if the App Group is unavailable.
    static var listsDirectory: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent("liiists", isDirectory: true)
        }
        // Fallback for testing / older installs
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("liiists", isDirectory: true)
    }

    /// Ensures the lists directory exists.
    static func ensureDirectory() {
        let dir = listsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Migrates lists from the old Documents/liiists location to the shared container.
    /// Call once on app launch.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let newDir = container.appendingPathComponent("liiists", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldDir = docs.appendingPathComponent("liiists", isDirectory: true)

        // Only migrate if old dir exists and new dir is empty or doesn't exist
        guard fm.fileExists(atPath: oldDir.path) else { return }

        ensureDirectory()

        guard let files = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) else { return }
        let mdFiles = files.filter { $0.pathExtension == "md" }
        guard !mdFiles.isEmpty else { return }

        // Check if new dir already has files (don't overwrite)
        let existingFiles = (try? fm.contentsOfDirectory(at: newDir, includingPropertiesForKeys: nil)) ?? []
        let existingMD = existingFiles.filter { $0.pathExtension == "md" }
        if !existingMD.isEmpty { return }

        // Move files
        for file in mdFiles {
            let dest = newDir.appendingPathComponent(file.lastPathComponent)
            try? fm.moveItem(at: file, to: dest)
        }
    }
}
