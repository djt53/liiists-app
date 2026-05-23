import Foundation

struct ListItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isChecked: Bool
    /// Populated only for entries belonging to a `.log` list. Minute-resolution,
    /// naive local datetime (no timezone). See decision 016.
    var timestamp: Date?

    init(id: UUID = UUID(), text: String, isChecked: Bool = false, timestamp: Date? = nil) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
        self.timestamp = timestamp
    }
}
