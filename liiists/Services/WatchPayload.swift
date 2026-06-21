import Foundation

/// The WatchConnectivity message contract between liiistsWatch and the iPhone
/// app. Encoded as `[String: Any]` so it survives the WC payload boundary
/// (sendMessage / transferUserInfo) without a custom Codable layer.
enum WatchPayload {
    /// Append a new item to the top of a regular or checklist list.
    case addItem(filename: String, text: String)

    /// Toggle a checklist item's done state.
    case toggleItem(filename: String, itemID: UUID)

    /// Append a timestamped entry to a log-type list. iPhone stamps `now`
    /// at the time of receipt.
    case appendLogEntry(filename: String, text: String)

    private enum Kind: String {
        case addItem
        case toggleItem
        case appendLogEntry
    }

    var dictionary: [String: Any] {
        switch self {
        case .addItem(let filename, let text):
            return [Key.kind: Kind.addItem.rawValue, Key.filename: filename, Key.text: text]
        case .toggleItem(let filename, let itemID):
            return [Key.kind: Kind.toggleItem.rawValue, Key.filename: filename, Key.itemID: itemID.uuidString]
        case .appendLogEntry(let filename, let text):
            return [Key.kind: Kind.appendLogEntry.rawValue, Key.filename: filename, Key.text: text]
        }
    }

    init?(message: [String: Any]) {
        guard let kindRaw = message[Key.kind] as? String,
              let kind = Kind(rawValue: kindRaw),
              let filename = message[Key.filename] as? String else { return nil }
        switch kind {
        case .addItem:
            guard let text = message[Key.text] as? String else { return nil }
            self = .addItem(filename: filename, text: text)
        case .toggleItem:
            guard let raw = message[Key.itemID] as? String,
                  let itemID = UUID(uuidString: raw) else { return nil }
            self = .toggleItem(filename: filename, itemID: itemID)
        case .appendLogEntry:
            guard let text = message[Key.text] as? String else { return nil }
            self = .appendLogEntry(filename: filename, text: text)
        }
    }

    private enum Key {
        static let kind = "kind"
        static let filename = "filename"
        static let text = "text"
        static let itemID = "itemID"
    }
}
