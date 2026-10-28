import XCTest
@testable import Drivy

/// Day grouping for `daily_scores` (S6): the day is the Europe/Madrid day the
/// server reads back (B1 of the QA report), and the upload path needs exact
/// ISO-8601 timestamps.
final class DriveDatesTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testTimestampsAreSentInUTCISO8601() {
        XCTAssertEqual(DriveISO8601.string(from: Self.reference), "2023-11-14T22:13:20Z")
    }

    func testDayKeyUsesTheInjectedCalendar() {
        XCTAssertEqual(DriveDay.key(for: Self.reference, calendar: utc), "2023-11-14")
    }

    func testDayKeyShiftsWithTheTimeZone() {
        // 22:13 UTC is already the next day at UTC+3.
        var ahead = Calendar(identifier: .gregorian)
        ahead.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .gmt

        XCTAssertEqual(DriveDay.key(for: Self.reference, calendar: ahead), "2023-11-15")
    }

    func testDayBoundsAreMidnightToNextMidnight() {
        let start = DriveDay.start(of: Self.reference, calendar: utc)
        let end = DriveDay.end(of: Self.reference, calendar: utc)

        XCTAssertEqual(start, Date(timeIntervalSince1970: 1_699_920_000)) // 2023-11-14T00:00:00Z
        XCTAssertEqual(end, Date(timeIntervalSince1970: 1_700_006_400)) // 2023-11-15T00:00:00Z
        XCTAssertTrue(end > start)
    }

    /// B1 of the QA report: without an explicit calendar the day is Madrid, the
    /// zone `madrid_today()` and the `day` CHECKs of the migration use. A Canarias
    /// device (one hour behind) at 23:30 has already crossed midnight in Madrid,
    /// and the lesson of that moment must be filed under the Madrid day or the
    /// server rejects it.
    func testTheDefaultDayIsTheMadridDay() {
        var canary = Calendar(identifier: .gregorian)
        canary.locale = Locale(identifier: "en_US_POSIX")
        canary.timeZone = TimeZone(identifier: "Atlantic/Canary") ?? .gmt

        // 23:30 in Canarias is 00:30 the next day in Madrid.
        let lateNight = canary.date(
            from: DateComponents(year: 2026, month: 1, day: 15, hour: 23, minute: 30)
        ) ?? Date(timeIntervalSince1970: 0)

        XCTAssertEqual(DriveDay.key(for: lateNight), "2026-01-16")
        // The device zone would have produced the day the server already closed.
        XCTAssertEqual(DriveDay.key(for: lateNight, calendar: canary), "2026-01-15")
    }
}
