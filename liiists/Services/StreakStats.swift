import Foundation

/// Computed stats for a single streak list.
struct StreakStatsResult: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletions: Int
    /// Completions logged in the current (ISO Monday-start) week.
    let thisWeekCount: Int
    /// Target completions for one week, per the cadence.
    let thisWeekTarget: Int
}

/// Pure functions for computing streak statistics.
///
/// All cadences reduce to a `(period, target)` model: a *period* (day or week)
/// is **met** when the number of completions falling inside it reaches the
/// cadence target. A streak is the run of consecutive met periods; the current,
/// still-in-progress period never *breaks* a streak — it just hasn't counted yet.
///
/// `entries` is the list of filled-completion dates and **may contain duplicates**
/// — multiple completions on the same day all count toward that day's total,
/// which is what makes `timesPerDay(n)` work.
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

        // Completions counted per day — duplicates on the same day accumulate.
        var perDay: [Date: Int] = [:]
        for date in entries {
            perDay[cal.startOfDay(for: date), default: 0] += 1
        }

        let currentStreak: Int
        let longestStreak: Int
        switch cadence.period {
        case .day:
            currentStreak = currentDayStreak(perDay: perDay, cadence: cadence, today: todayStart, cal: cal)
            longestStreak = longestDayStreak(perDay: perDay, cadence: cadence, cal: cal)
        case .week:
            currentStreak = currentWeekStreak(perDay: perDay, target: cadence.target, today: todayStart, cal: cal)
            longestStreak = longestWeekStreak(perDay: perDay, target: cadence.target, cal: cal)
        }

        let weekStart = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let thisWeekCount = perDay
            .filter { $0.key >= weekStart && $0.key <= todayStart }
            .values.reduce(0, +)

        return StreakStatsResult(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCompletions: entries.count,
            thisWeekCount: thisWeekCount,
            thisWeekTarget: cadence.weeklyTarget
        )
    }

    /// All cadence-eligible days from `start` to `today`, newest first.
    /// For the `weekdays` cadence, weekends are filtered out.
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

    // MARK: - Day-period streaks

    private static func currentDayStreak(
        perDay: [Date: Int], cadence: StreakCadence, today: Date, cal: Calendar
    ) -> Int {
        let target = cadence.target
        func eligible(_ d: Date) -> Bool { cadence.includesDay(d, calendar: cal) }
        func met(_ d: Date) -> Bool { (perDay[d] ?? 0) >= target }

        var streak = 0
        var day = today

        // If today is eligible but not yet met, start from the previous day —
        // today's period isn't over, so it can't break the streak yet.
        if eligible(day) && !met(day) {
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }

        while true {
            if eligible(day) {
                if met(day) { streak += 1 } else { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private static func longestDayStreak(
        perDay: [Date: Int], cadence: StreakCadence, cal: Calendar
    ) -> Int {
        guard let first = perDay.keys.min(), let last = perDay.keys.max() else { return 0 }
        let target = cadence.target

        var longest = 0
        var current = 0
        var day = first
        while day <= last {
            if cadence.includesDay(day, calendar: cal) {
                if (perDay[day] ?? 0) >= target {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return longest
    }

    // MARK: - Week-period streaks

    private static func weekCompletions(
        _ interval: DateInterval, perDay: [Date: Int]
    ) -> Int {
        perDay.filter { $0.key >= interval.start && $0.key < interval.end }
            .values.reduce(0, +)
    }

    private static func currentWeekStreak(
        perDay: [Date: Int], target: Int, today: Date, cal: Calendar
    ) -> Int {
        var streak = 0
        guard var interval = cal.dateInterval(of: .weekOfYear, for: today) else { return 0 }

        if weekCompletions(interval, perDay: perDay) >= target {
            streak += 1
        }
        // Otherwise: week in progress — don't count, but don't break either.

        guard let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: interval.start),
              let prev = cal.dateInterval(of: .weekOfYear, for: prevStart) else {
            return streak
        }
        interval = prev

        while true {
            if weekCompletions(interval, perDay: perDay) >= target {
                streak += 1
            } else {
                break
            }
            guard let ps = cal.date(byAdding: .weekOfYear, value: -1, to: interval.start),
                  let p = cal.dateInterval(of: .weekOfYear, for: ps) else { break }
            interval = p
        }
        return streak
    }

    private static func longestWeekStreak(
        perDay: [Date: Int], target: Int, cal: Calendar
    ) -> Int {
        guard let first = perDay.keys.min(), let last = perDay.keys.max() else { return 0 }

        var longest = 0
        var current = 0
        guard var interval = cal.dateInterval(of: .weekOfYear, for: first) else { return 0 }
        let endWeekEnd = cal.dateInterval(of: .weekOfYear, for: last)?.end ?? last

        while interval.start <= endWeekEnd {
            if weekCompletions(interval, perDay: perDay) >= target {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            guard let ns = cal.date(byAdding: .weekOfYear, value: 1, to: interval.start),
                  let n = cal.dateInterval(of: .weekOfYear, for: ns) else { break }
            interval = n
        }
        return longest
    }
}
