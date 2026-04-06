import Foundation

/// Shared container paths for App Group and iCloud Drive access.
/// Used by the main app, App Intents, and the Share Extension.
enum SharedContainer {
    static let appGroupID = "group.com.davidtingle.liiists"
    static let iCloudContainerID = "iCloud.com.davidtingle.liiists"

    /// The iCloud Drive Documents directory, if available.
    static var iCloudDocumentsDirectory: URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: iCloudContainerID
        ) else { return nil }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    /// The shared lists directory — prefers iCloud, falls back to App Group, then Documents.
    static var listsDirectory: URL {
        if let iCloud = iCloudDocumentsDirectory {
            return iCloud
        }
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent("liiists", isDirectory: true)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("liiists", isDirectory: true)
    }

    /// Whether iCloud Drive is available.
    static var isiCloudAvailable: Bool {
        iCloudDocumentsDirectory != nil
    }

    /// Ensures the lists directory exists.
    static func ensureDirectory() {
        let dir = listsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Migrates lists from the old Documents/liiists location to the App Group container.
    /// Call once on app launch.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let newDir = container.appendingPathComponent("liiists", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldDir = docs.appendingPathComponent("liiists", isDirectory: true)

        guard fm.fileExists(atPath: oldDir.path) else { return }

        if !fm.fileExists(atPath: newDir.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        }

        guard let files = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) else { return }
        let mdFiles = files.filter { $0.pathExtension == "md" }
        guard !mdFiles.isEmpty else { return }

        let existingFiles = (try? fm.contentsOfDirectory(at: newDir, includingPropertiesForKeys: nil)) ?? []
        let existingMD = existingFiles.filter { $0.pathExtension == "md" }
        if !existingMD.isEmpty { return }

        for file in mdFiles {
            let dest = newDir.appendingPathComponent(file.lastPathComponent)
            try? fm.moveItem(at: file, to: dest)
        }
    }

    /// Migrates lists from the App Group container to iCloud Drive.
    /// Copies files (not moves) for safety — originals remain until copy is confirmed.
    static func migrateToiCloudIfNeeded() {
        let fm = FileManager.default
        guard let iCloudDir = iCloudDocumentsDirectory else { return }
        guard let appGroupContainer = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let appGroupDir = appGroupContainer.appendingPathComponent("liiists", isDirectory: true)
        guard fm.fileExists(atPath: appGroupDir.path) else { return }

        // Ensure iCloud Documents directory exists
        if !fm.fileExists(atPath: iCloudDir.path) {
            try? fm.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
        }

        guard let sourceFiles = try? fm.contentsOfDirectory(at: appGroupDir, includingPropertiesForKeys: nil) else { return }
        let mdFiles = sourceFiles.filter { $0.pathExtension == "md" }
        guard !mdFiles.isEmpty else { return }

        // Don't overwrite if iCloud already has files (e.g. from another device)
        let existingFiles = (try? fm.contentsOfDirectory(at: iCloudDir, includingPropertiesForKeys: nil)) ?? []
        let existingMD = existingFiles.filter { $0.pathExtension == "md" }
        if !existingMD.isEmpty { return }

        // Copy files to iCloud using file coordination
        let coordinator = NSFileCoordinator()
        var copySuccess = true

        for file in mdFiles {
            let dest = iCloudDir.appendingPathComponent(file.lastPathComponent)
            var error: NSError?
            coordinator.coordinate(writingItemAt: dest, options: .forReplacing, error: &error) { coordURL in
                do {
                    try fm.copyItem(at: file, to: coordURL)
                } catch {
                    copySuccess = false
                }
            }
            if error != nil { copySuccess = false }
        }

        // Remove App Group copies only if all files migrated successfully
        if copySuccess {
            for file in mdFiles {
                try? fm.removeItem(at: file)
            }
        }
    }
}
