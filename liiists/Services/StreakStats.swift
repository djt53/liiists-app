import Foundation

/// Computed stats for a single streak list.
struct StreakStatsResult: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletions: Int
    let thisWeekCount: Int
    let thisWeekTarget: Int
}

/// Pure functions for computing streak statistics.
enum StreakStats {

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    static func compute(
        entries: [Date],
        cadence: StreakCadence,
        asOf today: Date = Date()
    ) -> StreakStatsResult {
        let cal = Self.calendar
        let todayStart = cal.startOfDay(for: today)
        let entrySet = Set(entries.map { cal.startOfDay(for: $0) })

        let currentStreak = computeCurrentStreak(
            entries: entrySet, cadence: cadence, from: todayStart, calendar: cal
        )
        let longestStreak = computeLongestStreak(
            entries: entrySet, cadence: cadence, calendar: cal
        )

        let weekStart = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let thisWeekCount = entrySet.filter { $0 >= weekStart && $0 <= todayStart }.count

        return StreakStatsResult(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCompletions: entries.count,
            thisWeekCount: thisWeekCount,
            thisWeekTarget: cadence.weeklyTarget
        )
    }

    /// All cadence-eligible days from `start` to `today`, newest first.
    /// For weekdays cadence, weekends are filtered out.
    static func eligibleDays(
        from start: Date,
        cadence: StreakCadence,
        asOf today: Date = Date()
    ) -> [Date] {
        let cal = Self.calendar
        let startDay = cal.startOfDay(for: start)
        let todayStart = cal.startOfDay(for: today)
        guard startDay <= todayStart else { return [] }

        var days: [Date] = []
        var day = todayStart
        while day >= startDay {
            if cadence.includesDay(day, calendar: cal) {
                days.append(day)
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return days
    }

    // MARK: - Private

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

        case .threePerWeek:
            return countConsecutiveWeeks(entries: entries, from: today, target: 3, calendar: calendar)
        }
    }

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
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        return streak
    }

    private static func countConsecutiveWeeks(
        entries: Set<Date>, from today: Date, target: Int, calendar: Calendar
    ) -> Int {
        var streak = 0

        guard var weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }

        let currentWeekCount = entries.filter {
            $0 >= weekInterval.start && $0 < weekInterval.end
        }.count

        if currentWeekCount >= target {
            streak += 1
        }
        // Otherwise: week in progress — don't count, but also don't break.

        guard let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
              let prevInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekStart) else {
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

        case .threePerWeek:
            var longest = 0
            var current = 0
            guard var weekInterval = calendar.dateInterval(of: .weekOfYear, for: first) else { return 0 }
            let endWeek = calendar.dateInterval(of: .weekOfYear, for: last)?.end ?? last

            while weekInterval.start <= endWeek {
                let count = entries.filter { $0 >= weekInterval.start && $0 < weekInterval.end }.count
                if count >= 3 {
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
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return longest
    }
}
