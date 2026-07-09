import XCTest
@testable import liiists

/// Covers the generalized cadence grammar (daily / weekdays / N/day / N/week),
/// backward compatibility with the legacy "3/week", and markdown round-trip.
final class StreakCadenceTests: XCTestCase {

    func testParseKnownForms() {
        XCTAssertEqual(StreakCadence.from("daily"), .daily)
        XCTAssertEqual(StreakCadence.from("weekdays"), .weekdays)
        XCTAssertEqual(StreakCadence.from("3/day"), .timesPerDay(3))
        XCTAssertEqual(StreakCadence.from("5/week"), .timesPerWeek(5))
    }

    func testParseLegacyThreePerWeek() {
        // Files written by earlier builds used "3/week" for the old .threePerWeek.
        XCTAssertEqual(StreakCadence.from("3/week"), .timesPerWeek(3))
    }

    func testParseNormalizesAndFallsBack() {
        XCTAssertEqual(StreakCadence.from("1/day"), .daily)      // normalized
        XCTAssertEqual(StreakCadence.from(" WEEKDAYS "), .weekdays) // trim + case
        XCTAssertEqual(StreakCadence.from("garbage"), .daily)   // fallback
        XCTAssertEqual(StreakCadence.from("0/week"), .timesPerWeek(1)) // clamped
    }

    func testMarkdownStringRoundTrip() {
        let cases: [StreakCadence] = [.daily, .weekdays, .timesPerDay(3), .timesPerWeek(4)]
        for c in cases {
            XCTAssertEqual(StreakCadence.from(c.markdownString), c, "round-trip failed for \(c)")
        }
    }

    func testMarkdownStrings() {
        XCTAssertEqual(StreakCadence.daily.markdownString, "daily")
        XCTAssertEqual(StreakCadence.weekdays.markdownString, "weekdays")
        XCTAssertEqual(StreakCadence.timesPerDay(3).markdownString, "3/day")
        XCTAssertEqual(StreakCadence.timesPerWeek(3).markdownString, "3/week")
    }

    func testPeriodAndTarget() {
        XCTAssertEqual(StreakCadence.daily.period, .day)
        XCTAssertEqual(StreakCadence.daily.target, 1)
        XCTAssertEqual(StreakCadence.timesPerDay(4).period, .day)
        XCTAssertEqual(StreakCadence.timesPerDay(4).target, 4)
        XCTAssertEqual(StreakCadence.timesPerWeek(4).period, .week)
        XCTAssertEqual(StreakCadence.timesPerWeek(4).target, 4)
    }

    // MARK: - Full file round-trip through MarkdownParser

    func testStreakFileRoundTripPreservesCadenceAndMultiPerDay() {
        let content = """
        ---
        title: Pushups
        type: streak
        cadence: 3/day
        ---
        - 2026-07-08
        - 2026-07-08
        - 2026-07-08
        - 2026-07-07
        """
        let parsed = MarkdownParser.parse(content: content, filename: "pushups.md")
        XCTAssertEqual(parsed.type, .streak)
        XCTAssertEqual(parsed.streakCadence, .timesPerDay(3))
        XCTAssertEqual(parsed.streakEntries.count, 4)
        // Three completions land on the same day — the multi-per-day path.
        let cal = Calendar(identifier: .iso8601)
        let jul8 = parsed.streakEntries.filter {
            cal.component(.day, from: $0.date) == 8 && cal.component(.month, from: $0.date) == 7
        }
        XCTAssertEqual(jul8.count, 3)

        // Re-serialize and re-parse — cadence + entry count survive.
        let written = MarkdownParser.write(parsed)
        XCTAssertTrue(written.contains("cadence: 3/day"))
        let reparsed = MarkdownParser.parse(content: written, filename: "pushups.md")
        XCTAssertEqual(reparsed.streakCadence, .timesPerDay(3))
        XCTAssertEqual(reparsed.streakEntries.count, 4)
    }
}
