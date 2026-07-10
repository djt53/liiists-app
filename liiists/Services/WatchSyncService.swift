import Foundation
import WatchConnectivity
import WidgetKit

/// WatchConnectivity on the iPhone side. Receives payloads from the
/// liiistsWatch companion and routes them to `ListStore`. iPhone remains
/// the single source of truth for iCloud Drive markdown writes — the watch
/// just sends intent.
@MainActor
final class WatchSyncService: NSObject, ObservableObject {
    static let shared = WatchSyncService()

    private weak var listStore: ListStore?

    func activate(listStore: ListStore) {
        self.listStore = listStore
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Pushes the current catalog data to the watch via
    /// `updateApplicationContext`. This is the textbook pattern for
    /// "latest snapshot from iPhone to Watch" — WC delivers it
    /// opportunistically next time the watch wakes, replacing any prior
    /// context. App Groups don't span iPhone↔Watch, so the catalog must
    /// physically travel the wire; writing it to the iPhone's local
    /// App Group is a no-op as far as the watch is concerned.
    func notifyCatalogUpdated() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Read the catalog the iPhone just wrote to its local App Group
        // and re-encode for transport. (Source of truth is in memory in
        // ListStore but we already do the projection in the sync helper.)
        let entries = WatchCatalog.read()
        guard let payload = try? JSONEncoder().encode(entries) else { return }

        let context: [String: Any] = [
            Message.kind: Message.catalogSnapshot,
            Message.payload: payload,
            Message.pinned: WatchCatalog.pinnedFilename ?? "",
            Message.revision: ISO8601DateFormatter().string(from: Date()),
        ]

        do {
            try session.updateApplicationContext(context)
        } catch {
            // applicationContext throws when the new payload is identical
            // to the last one or exceeds ~65KB. Both are recoverable —
            // the watch will get the next update.
        }
    }

    enum Message {
        static let kind = "kind"
        static let catalogSnapshot = "catalogSnapshot"
        static let payload = "payload"
        static let pinned = "pinned"
        static let revision = "revision"
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            replyHandler(self.handle(message: message))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = self.handle(message: userInfo)
        }
    }
}

@MainActor
private extension WatchSyncService {
    func handle(message: [String: Any]) -> [String: Any] {
        guard let payload = WatchPayload(message: message) else {
            return ["ok": false, "error": "invalid_payload"]
        }
        guard let store = listStore else {
            return ["ok": false, "error": "store_unavailable"]
        }
        switch payload {
        case .addItem(let filename, let text):
            return applyMutation(filename: filename, store: store) { list in
                list.items.insert(ListItem(text: text), at: 0)
                return true
            }
        case .toggleItem(let filename, let itemID):
            return applyMutation(filename: filename, store: store) { list in
                guard let idx = list.items.firstIndex(where: { $0.id == itemID }) else { return false }
                list.items[idx].isChecked.toggle()
                return true
            }
        case .appendLogEntry(let filename, let text):
            return applyMutation(filename: filename, store: store) { list in
                var entry = ListItem(text: text)
                entry.timestamp = Date()
                list.items.insert(entry, at: 0)
                return true
            }
        case .logStreakToday(let filename):
            return applyMutation(filename: filename, store: store) { list in
                guard list.type == .streak else { return false }
                let cadence = list.streakCadence ?? .daily
                let today = Date()
                // Binary-per-day cadences (daily / weekdays / X-a-week) toggle
                // today on and off — one tap means "logged today". Only X/day
                // accumulates multiple completions in a single day, so it adds
                // one per tap toward the daily target.
                if cadence.dailyTarget == 1, list.isStreakDayLogged(today) {
                    list.setStreakDay(today, filled: false)
                } else {
                    list.addStreakEntry(today)
                }
                return true
            }
        case .unlogStreakToday(let filename):
            return applyMutation(filename: filename, store: store) { list in
                guard list.type == .streak else { return false }
                let cal = Calendar.current
                guard let idx = list.streakEntries.lastIndex(where: {
                    $0.filled && cal.isDateInToday($0.date)
                }) else { return false }
                list.removeStreakEntry(at: idx)
                return true
            }
        }
    }

    /// Apply a mutation to a list identified by filename. The closure
    /// returns `false` when the mutation couldn't be applied (e.g. item
    /// not found in a checklist toggle).
    func applyMutation(
        filename: String,
        store: ListStore,
        mutate: (inout ItemList) -> Bool
    ) -> [String: Any] {
        guard let idx = store.lists.firstIndex(where: { $0.filename == filename }) else {
            return ["ok": false, "error": "list_not_found"]
        }
        var list = store.lists[idx]
        guard mutate(&list) else {
            return ["ok": false, "error": "item_not_found"]
        }
        store.update(list)
        WidgetCenter.shared.reloadAllTimelines()
        return ["ok": true]
    }
}
