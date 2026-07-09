import XCTest
@testable import liiists

/// Covers the generalized `(period, target)` streak model: daily, weekdays,
/// timesPerDay(n), timesPerWeek(n) — persist, break, in-progress, and the
/// multiple-completions-per-day path that makes `timesPerDay` work.
final class StreakStatsTests: XCTestCase {

    // Reference week (ISO, Monday-start):
    //   Jul 6 Mon · 7 Tue · 8 Wed · 9 Thu · 10 Fri · 11 Sat · 12 Sun (2026)
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private let wed = { () -> Date in
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 8; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // MARK: - Daily

    func testDailyConsecutiveStreak() {
        let entries = [d(2026, 7, 6), d(2026, 7, 7), d(2026, 7, 8)]
        let r = StreakStats.compute(entries: entries, cadence: .daily, asOf: wed)
        XCTAssertEqual(r.currentStreak, 3)
        XCTAssertEqual(r.longestStreak, 3)
        XCTAssertEqual(r.totalCompletions, 3)
    }

    func testDailyTodayNotYetLoggedDoesNotBreak() {
        // Mon + Tue logged, Wed (today) not yet — streak holds at 2.
        let entries = [d(2026, 7, 6), d(2026, 7, 7)]
        let r = StreakStats.compute(entries: entries, cadence: .daily, asOf: wed)
        XCTAssertEqual(r.currentStreak, 2)
    }

    func testDailyGapBreaksStreak() {
        // Mon + Wed(today), Tue missing — only today counts.
        let entries = [d(2026, 7, 6), d(2026, 7, 8)]
        let r = StreakStats.compute(entries: entries, cadence: .daily, asOf: wed)
        XCTAssertEqual(r.currentStreak, 1)
    }

    func testDailyEmpty() {
        let r = StreakStats.compute(entries: [], cadence: .daily, asOf: wed)
        XCTAssertEqual(r.currentStreak, 0)
        XCTAssertEqual(r.longestStreak, 0)
        XCTAssertEqual(r.totalCompletions, 0)
    }

    func testDailyLongestFromHistory() {
        // Old run of 3, recent run of 2 → longest 3, current 2.
        let entries = [
            d(2026, 6, 1), d(2026, 6, 2), d(2026, 6, 3),   // 3 consecutive
            d(2026, 7, 7), d(2026, 7, 8)                   // Tue+Wed(today)
        ]
        let r = StreakStats.compute(entries: entries, cadence: .daily, asOf: wed)
        XCTAssertEqual(r.longestStreak, 3)
        XCTAssertEqual(r.currentStreak, 2)
    }

    // MARK: - Weekdays

    func testWeekdaysWeekendDoesNotBreak() {
        // asOf Mon Jul 6. Logged Fri Jul 3 + Mon Jul 6; Sat/Sun are ineligible,
        // so the streak spans the weekend uninterrupted → 2.
        let entries = [d(2026, 7, 3), d(2026, 7, 6)]
        let r = StreakStats.compute(entries: entries, cadence: .weekdays, asOf: d(2026, 7, 6))
        XCTAssertEqual(r.currentStreak, 2)
    }

    func testWeekdaysMissedWeekdayBreaks() {
        // asOf Fri Jul 10. Logged Mon, Tue, (skip Wed), Thu, Fri.
        // Wed missing breaks it → only Thu+Fri count = 2.
        let entries = [d(2026, 7, 6), d(2026, 7, 7), d(2026, 7, 9), d(2026, 7, 10)]
        let r = StreakStats.compute(entries: entries, cadence: .weekdays, asOf: d(2026, 7, 10))
        XCTAssertEqual(r.currentStreak, 2)
    }

    // MARK: - timesPerDay(n) — the multi-completion-per-day path

    func testTimesPerDayCountsMultipleSameDayEntries() {
        // Target 2/day. Wed×2, Tue×2 met; Mon×1 falls short → break at Mon.
        let entries = [
            d(2026, 7, 8), d(2026, 7, 8),   // Wed ×2 (today, met)
            d(2026, 7, 7), d(2026, 7, 7),   // Tue ×2 (met)
            d(2026, 7, 6)                    // Mon ×1 (short)
        ]
        let r = StreakStats.compute(entries: entries, cadence: .timesPerDay(2), asOf: wed)
        XCTAssertEqual(r.currentStreak, 2)
        XCTAssertEqual(r.longestStreak, 2)
        XCTAssertEqual(r.totalCompletions, 5)
    }

    func testTimesPerDayTodayPartialDoesNotBreak() {
        // Target 3/day. Today has only 1 (in progress) — doesn't break;
        // Tue had 3 → streak holds at 1 (yesterday).
        let entries = [
            d(2026, 7, 8),                                  // Wed ×1 (partial today)
            d(2026, 7, 7), d(2026, 7, 7), d(2026, 7, 7)     // Tue ×3 (met)
        ]
        let r = StreakStats.compute(entries: entries, cadence: .timesPerDay(3), asOf: wed)
        XCTAssertEqual(r.currentStreak, 1)
    }

    // MARK: - timesPerWeek(n)

    func testTimesPerWeekConsecutiveWeeks() {
        // Target 3/week. This week (Mon–Wed ×3) + prior week (×3) → 2.
        let entries = [
            d(2026, 7, 6), d(2026, 7, 7), d(2026, 7, 8),    // this week ×3
            d(2026, 6, 29), d(2026, 6, 30), d(2026, 7, 1)   // prior week ×3
        ]
        let r = StreakStats.compute(entries: entries, cadence: .timesPerWeek(3), asOf: wed)
        XCTAssertEqual(r.currentStreak, 2)
    }

    func testTimesPerWeekCurrentWeekShortDoesNotBreak() {
        // This week only 2 (in progress, <3) — not counted, not broken.
        // Prior week met → streak 1.
        let entries = [
            d(2026, 7, 6), d(2026, 7, 7),                   // this week ×2
            d(2026, 6, 29), d(2026, 6, 30), d(2026, 7, 1)   // prior week ×3
        ]
        let r = StreakStats.compute(entries: entries, cadence: .timesPerWeek(3), asOf: wed)
        XCTAssertEqual(r.currentStreak, 1)
    }

    func testThisWeekCountAndTarget() {
        let entries = [d(2026, 7, 6), d(2026, 7, 7), d(2026, 7, 8)]
        let daily = StreakStats.compute(entries: entries, cadence: .daily, asOf: wed)
        XCTAssertEqual(daily.thisWeekCount, 3)
        XCTAssertEqual(daily.thisWeekTarget, 7)

        let perWeek = StreakStats.compute(entries: entries, cadence: .timesPerWeek(3), asOf: wed)
        XCTAssertEqual(perWeek.thisWeekCount, 3)
        XCTAssertEqual(perWeek.thisWeekTarget, 3)
    }
}
