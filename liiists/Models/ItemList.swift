import Foundation

/// Represents a single liiists list backed by a markdown file.
struct ItemList: Identifiable, Equatable {
    let id: UUID
    var filename: String
    var title: String
    var type: ListType
    var createdDate: Date?
    var modifiedDate: Date?
    var items: [ListItem]

    /// Cadence — only populated when `type == .streak`.
    var streakCadence: StreakCadence?

    /// Completion dates — only populated when `type == .streak`.
    var streakEntries: [Date]

    /// Extra frontmatter keys we don't recognize — preserved on round-trip.
    var extraFrontmatter: [String: String]

    enum ListType: String, Equatable {
        case list
        case checklist
        case streak
        case log
    }

    init(
        id: UUID = UUID(),
        filename: String,
        title: String? = nil,
        type: ListType = .list,
        createdDate: Date? = nil,
        modifiedDate: Date? = nil,
        items: [ListItem] = [],
        streakCadence: StreakCadence? = nil,
        streakEntries: [Date] = [],
        extraFrontmatter: [String: String] = [:]
    ) {
        self.id = id
        self.filename = filename
        self.title = title ?? Self.titleFromFilename(filename)
        self.type = type
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.items = items
        self.streakCadence = streakCadence
        self.streakEntries = streakEntries
        self.extraFrontmatter = extraFrontmatter
    }

    var itemCount: Int { items.count }
    var checkedCount: Int { items.filter(\.isChecked).count }

    /// Mutates `streakEntries` by toggling today on/off.
    mutating func toggleStreakDay(_ date: Date, calendar: Calendar = .current) {
        let target = calendar.startOfDay(for: date)
        if let idx = streakEntries.firstIndex(where: { calendar.startOfDay(for: $0) == target }) {
            streakEntries.remove(at: idx)
        } else {
            streakEntries.insert(target, at: 0)
            streakEntries.sort(by: >)
        }
    }

    func isStreakDayLogged(_ date: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: date)
        return streakEntries.contains { calendar.startOfDay(for: $0) == target }
    }

    /// Convert a slug filename to a display title.
    /// "books-to-read.md" → "Books to Read"
    static func titleFromFilename(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Convert a display title to a slug filename.
    /// "Books to Read" → "books-to-read.md"
    static func filenameFromTitle(_ title: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug + ".md"
    }
}

/// How often a streak expects to be logged.
enum StreakCadence: Equatable {
    case daily
    case weekdays
    case threePerWeek

    /// Parse from markdown string: "daily", "weekdays", "3/week"
    static func from(_ string: String) -> StreakCadence {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "weekdays" { return .weekdays }
        if trimmed == "3/week" { return .threePerWeek }
        return .daily
    }

    /// Serialize to markdown string.
    var markdownString: String {
        switch self {
        case .daily: return "daily"
        case .weekdays: return "weekdays"
        case .threePerWeek: return "3/week"
        }
    }

    /// Human-readable label for UI.
    var displayLabel: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .threePerWeek: return "3x / week"
        }
    }

    /// Weekly target count for progress display.
    var weeklyTarget: Int {
        switch self {
        case .daily: return 7
        case .weekdays: return 5
        case .threePerWeek: return 3
        }
    }

    /// Whether a given calendar day is "expected" per the cadence.
    /// (Used to decide whether to render a circle for a past day.)
    func includesDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily, .threePerWeek:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6 // Mon-Fri
        }
    }
}
