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

    /// Completion circles, newest-first — only populated when `type == .streak`.
    /// Each entry is one circle in the row; unfilled entries persist as empty
    /// placeholders so undoing a completion never reflows the grid.
    var streakEntries: [StreakEntry]

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
        streakEntries: [StreakEntry] = [],
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

    /// Number of filled completions — drives the home badge and header count.
    var streakLoggedCount: Int { streakEntries.filter(\.filled).count }

    /// Sets the filled state of every entry on `day` (day granularity). Turning
    /// on with no existing entry creates one; turning off flips existing entries
    /// to unfilled placeholders. Used by the week view's per-day toggle.
    mutating func setStreakDay(_ day: Date, filled: Bool, calendar: Calendar = .current) {
        let target = calendar.startOfDay(for: day)
        let existing = streakEntries.indices.filter {
            calendar.startOfDay(for: streakEntries[$0].date) == target
        }
        if existing.isEmpty {
            if filled { addStreakEntry(day, calendar: calendar) }
        } else {
            for i in existing { streakEntries[i].filled = filled }
        }
    }

    /// Whether a filled completion exists for `date`'s calendar day.
    func isStreakDayLogged(_ date: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: date)
        return streakEntries.contains { $0.filled && calendar.startOfDay(for: $0.date) == target }
    }

    /// Inserts a new *filled* completion for `date` (day resolution) at the
    /// front of its date group, keeping the row newest-first.
    mutating func addStreakEntry(_ date: Date = Date(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let idx = streakEntries.firstIndex { $0.date < day } ?? streakEntries.count
        streakEntries.insert(StreakEntry(date: day, filled: true), at: idx)
    }

    /// Toggles the filled state of the entry at `index` in place. The slot stays
    /// in the row either way — an unfilled circle is a persistent placeholder.
    mutating func toggleStreakEntry(at index: Int) {
        guard streakEntries.indices.contains(index) else { return }
        streakEntries[index].filled.toggle()
    }

    /// Permanently removes the entry at `index` (the long-press "Remove" path).
    mutating func removeStreakEntry(at index: Int) {
        guard streakEntries.indices.contains(index) else { return }
        streakEntries.remove(at: index)
    }

    /// Re-dates the entry at `index`, preserving its filled state, and
    /// re-positions it so the row stays newest-first.
    mutating func updateStreakEntry(at index: Int, to date: Date, calendar: Calendar = .current) {
        guard streakEntries.indices.contains(index) else { return }
        var entry = streakEntries.remove(at: index)
        entry.date = calendar.startOfDay(for: date)
        let idx = streakEntries.firstIndex { $0.date < entry.date } ?? streakEntries.count
        streakEntries.insert(entry, at: idx)
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

/// One circle in a streak row: a dated completion that can be toggled between
/// filled (completed) and unfilled (a persistent empty placeholder). New
/// entries are born filled from the add-button; toggling never removes the slot.
struct StreakEntry: Equatable {
    var date: Date   // day resolution (start-of-day)
    var filled: Bool
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
