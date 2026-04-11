import Foundation

/// A single habit/streak within a streak list.
/// Each section has a name, cadence target, and a set of completion dates.
struct StreakSection: Identifiable, Equatable {
    let id: UUID
    var name: String
    var cadence: StreakCadence
    var entries: [Date] // completed dates, sorted descending

    init(id: UUID = UUID(), name: String, cadence: StreakCadence = .daily, entries: [Date] = []) {
        self.id = id
        self.name = name
        self.cadence = cadence
        self.entries = entries
    }

    /// Whether today has been logged.
    func isLoggedToday(calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: Date())
        return entries.contains { calendar.startOfDay(for: $0) == today }
    }

    /// Toggle today's entry — add if missing, remove if present.
    mutating func toggleToday(calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: Date())
        if let idx = entries.firstIndex(where: { calendar.startOfDay(for: $0) == today }) {
            entries.remove(at: idx)
        } else {
            entries.insert(today, at: 0)
        }
    }
}

/// How often a streak expects to be logged.
enum StreakCadence: Equatable {
    case daily
    case weekdays
    case perWeek(Int) // e.g. .perWeek(3) = 3 times per week

    /// Parse from markdown string: "daily", "weekdays", "3/week"
    static func from(_ string: String) -> StreakCadence {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "daily" { return .daily }
        if trimmed == "weekdays" { return .weekdays }
        if trimmed.hasSuffix("/week"), let n = Int(trimmed.replacingOccurrences(of: "/week", with: "")) {
            return .perWeek(max(1, min(n, 7)))
        }
        return .daily
    }

    /// Serialize to markdown string.
    var markdownString: String {
        switch self {
        case .daily: return "daily"
        case .weekdays: return "weekdays"
        case .perWeek(let n): return "\(n)/week"
        }
    }

    /// Human-readable label for UI.
    var displayLabel: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .perWeek(let n): return "\(n)x / week"
        }
    }

    /// Weekly target count for progress display.
    var weeklyTarget: Int {
        switch self {
        case .daily: return 7
        case .weekdays: return 5
        case .perWeek(let n): return n
        }
    }
}
