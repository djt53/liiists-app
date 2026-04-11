import Foundation

/// A single dot in the streak grid.
struct GridDot: Identifiable {
    let id = UUID()
    let date: Date
    let completed: Bool
    /// Whether this day was expected per cadence (false = weekend for weekdays cadence, etc.)
    let isExpected: Bool
}

/// Computed stats for a single streak section.
struct StreakStatsResult: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletions: Int
    let thisWeekCount: Int
    let thisWeekTarget: Int
}

/// Pure functions for computing streak statistics and grid data.
enum StreakStats {

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    // MARK: - Stats

    static func compute(for section: StreakSection, asOf today: Date = Date()) -> StreakStatsResult {
        let cal = Self.calendar
        let todayStart = cal.startOfDay(for: today)
        let entrySet = Set(section.entries.map { cal.startOfDay(for: $0) })

        let currentStreak = computeCurrentStreak(
            entries: entrySet, cadence: section.cadence, from: todayStart, calendar: cal
        )
        let longestStreak = computeLongestStreak(
            entries: entrySet, cadence: section.cadence, calendar: cal
        )

        // This week progress
        let weekStart = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let thisWeekCount = entrySet.filter { $0 >= weekStart && $0 <= todayStart }.count

        return StreakStatsResult(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCompletions: section.entries.count,
            thisWeekCount: thisWeekCount,
            thisWeekTarget: section.cadence.weeklyTarget
        )
    }

    // MARK: - Grid

    /// Generate grid dots for the last N weeks (7 columns per row, Mon-Sun).
    static func gridDots(for section: StreakSection, weeks: Int = 8, asOf today: Date = Date()) -> [[GridDot]] {
        let cal = Self.calendar
        let todayStart = cal.startOfDay(for: today)
        let entrySet = Set(section.entries.map { cal.startOfDay(for: $0) })

        // Find the Monday of the current week
        let weekday = cal.component(.weekday, from: todayStart)
        // ISO weekday: Mon=2, Sun=1. Days since Monday:
        let daysSinceMonday = (weekday + 5) % 7
        guard let currentMonday = cal.date(byAdding: .day, value: -daysSinceMonday, to: todayStart) else {
            return []
        }

        // Go back (weeks - 1) weeks to get the start
        guard let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentMonday) else {
            return []
        }

        var rows: [[GridDot]] = []
        var day = gridStart

        for _ in 0..<weeks {
            var row: [GridDot] = []
            for _ in 0..<7 {
                if day <= todayStart {
                    let completed = entrySet.contains(day)
                    let expected = isDayExpected(day, cadence: section.cadence, calendar: cal)
                    row.append(GridDot(date: day, completed: completed, isExpected: expected))
                } else {
                    // Future day — not expected, not completed
                    row.append(GridDot(date: day, completed: false, isExpected: false))
                }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
            rows.append(row)
        }

        return rows
    }

    // MARK: - Private

    /// Whether a given day is "expected" per the cadence.
    private static func isDayExpected(_ date: Date, cadence: StreakCadence, calendar: Calendar) -> Bool {
        switch cadence {
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6 // Mon-Fri
        case .perWeek:
            // For N/week, every day is potentially valid — streak breaks at week boundary
            return true
        }
    }

    /// Compute the current streak counting backward from today.
    private static func computeCurrentStreak(
        entries: Set<Date>, cadence: StreakCadence, from today: Date, calendar: Calendar
    ) -> Int {
        switch cadence {
        case .daily:
            return countConsecutiveDays(entries: entries, from: today, calendar: calendar) { _ in true }

        case .weekdays:
            return countConsecutiveDays(entries: entries, from: today, calendar: calendar) { date in
                let wd = calendar.component(.weekday, from: date)
                return wd >= 2 && wd <= 6
            }

        case .perWeek(let target):
            return countConsecutiveWeeks(entries: entries, from: today, target: target, calendar: calendar)
        }
    }

    /// Count consecutive days backward where every expected day has an entry.
    private static func countConsecutiveDays(
        entries: Set<Date>, from today: Date, calendar: Calendar, isExpected: (Date) -> Bool
    ) -> Int {
        var streak = 0
        var day = today

        // If today is expected but not yet logged, start from yesterday
        // (the day isn't over yet — don't penalize for not logging yet today)
        if isExpected(day) && !entries.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        while true {
            if isExpected(day) {
                if entries.contains(day) {
                    streak += 1
                } else {
                    break
                }
            }
            // Skip non-expected days (e.g. weekends for weekdays cadence)
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        return streak
    }

    /// Count consecutive weeks backward where each week meets the target count.
    private static func countConsecutiveWeeks(
        entries: Set<Date>, from today: Date, target: Int, calendar: Calendar
    ) -> Int {
        var streak = 0

        // Start from the current week
        guard var weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }

        // Current week is in progress — check if target is already met
        let currentWeekCount = entries.filter {
            $0 >= weekInterval.start && $0 < weekInterval.end
        }.count

        // If current week already meets target, count it
        if currentWeekCount >= target {
            streak += 1
        } else if currentWeekCount == 0 {
            // Current week has no entries — don't penalize (week in progress),
            // but also don't count it. Start checking from last week.
        } else {
            // Some entries but not enough — week in progress, skip to previous
        }

        // Check previous weeks
        guard let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start) else {
            return streak
        }
        guard let prevInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekStart) else {
            return streak
        }
        weekInterval = prevInterval

        while true {
            let weekCount = entries.filter {
                $0 >= weekInterval.start && $0 < weekInterval.end
            }.count

            if weekCount >= target {
                streak += 1
            } else {
                break
            }

            guard let prevStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
                  let prev = calendar.dateInterval(of: .weekOfYear, for: prevStart) else { break }
            weekInterval = prev
        }

        return streak
    }

    /// Compute the longest streak across all time.
    private static func computeLongestStreak(
        entries: Set<Date>, cadence: StreakCadence, calendar: Calendar
    ) -> Int {
        guard !entries.isEmpty else { return 0 }

        let sorted = entries.sorted()
        guard let first = sorted.first, let last = sorted.last else { return 0 }

        switch cadence {
        case .daily:
            return longestConsecutiveDays(sorted: sorted, calendar: calendar) { _ in true }

        case .weekdays:
            return longestConsecutiveDays(sorted: sorted, calendar: calendar) { date in
                let wd = calendar.component(.weekday, from: date)
                return wd >= 2 && wd <= 6
            }

        case .perWeek(let target):
            // Walk week by week from first entry to last
            var longest = 0
            var current = 0
            guard var weekInterval = calendar.dateInterval(of: .weekOfYear, for: first) else { return 0 }
            let endWeek = calendar.dateInterval(of: .weekOfYear, for: last)?.end ?? last

            while weekInterval.start <= endWeek {
                let count = entries.filter { $0 >= weekInterval.start && $0 < weekInterval.end }.count
                if count >= target {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
                guard let nextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: weekInterval.start),
                      let next = calendar.dateInterval(of: .weekOfYear, for: nextStart) else { break }
                weekInterval = next
            }
            return longest
        }
    }

    /// Find the longest run of consecutive expected days with entries.
    private static func longestConsecutiveDays(
        sorted: [Date], calendar: Calendar, isExpected: (Date) -> Bool
    ) -> Int {
        guard let first = sorted.first, let last = sorted.last else { return 0 }

        let entrySet = Set(sorted)
        var longest = 0
        var current = 0
        var day = first

        while day <= last {
            if isExpected(day) {
                if entrySet.contains(day) {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            // Skip non-expected days without breaking streak
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return longest
    }
}
