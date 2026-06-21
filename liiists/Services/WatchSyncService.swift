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

    /// Pushes a lightweight nudge to the watch so it can reload complications
    /// after the iPhone has updated the App Group catalog. The catalog itself
    /// is the contract — the message is just a wake-up signal.
    func notifyCatalogUpdated() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([Message.kind: Message.catalogUpdated], replyHandler: nil) { _ in
            // Silent — the App Group write is the durable contract.
        }
    }

    private enum Message {
        static let kind = "kind"
        static let catalogUpdated = "catalogUpdated"
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
