import XCTest
@testable import Drivy

/// B1 of the QA report: every day and week key that is written to Supabase, or
/// compared with a server day, is built in Europe/Madrid, the zone the migration
/// pins (`madrid_today()`, `madrid_week_start()`, the `day` CHECKs of
/// `20261028084225_0002_duolingo_loop.sql`). The device zone is only for display.
final class MadridDayKeysTests: XCTestCase {

    /// Atlantic/Canary, one hour behind Madrid in winter.
    private var canary: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Atlantic/Canary") ?? .gmt
        return calendar
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Wall clock of `canary`, so the fixtures read like the device they describe.
    private func canaryInstant(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        canary.date(
            from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    func testTheSharedCalendarIsOneMadridGregorianCalendar() {
        XCTAssertEqual(Calendar.madrid.timeZone.identifier, "Europe/Madrid")
        XCTAssertEqual(Calendar.madrid.locale?.identifier, "en_US_POSIX")
        // The league week exposes the same calendar under its own name instead of
        // building a second one, so both flows can never drift apart.
        XCTAssertEqual(PublicLeagueWeek.madridCalendar, Calendar.madrid)
    }

    /// Sunday 23:30 in Canarias is Monday 00:30 in Madrid: the week that has just
    /// started, not the one that is ending.
    func testMondayKeyOnSundayNightInCanariasIsTheNextMonday() {
        let instant = canaryInstant(18, 23, 30)

        XCTAssertEqual(WeekBounds.mondayKey(for: instant), "2026-01-19")
        // The device zone would ask the server for the week it just closed.
        XCTAssertEqual(WeekBounds.mondayKey(for: instant, calendar: canary), "2026-01-12")
    }

    /// The countdown of the public league reads the same Madrid week (S5).
    func testTheLeagueCountdownStartsTheMadridWeek() {
        let instant = canaryInstant(18, 23, 30)

        XCTAssertEqual(PublicLeagueWeek.daysLeft(now: instant), 7)
    }

    /// Parsing a stored day key yields Madrid midnight, the same value
    /// `DriveDay.start` computes, so a day read from `daily_scores` and a day
    /// computed from a clock compare equal.
    func testParsingADayKeyYieldsMadridMidnight() {
        let madridMidnight = utc.date(
            from: DateComponents(year: 2026, month: 1, day: 15, hour: 23)
        )

        XCTAssertEqual(DayKey.date(from: "2026-01-16"), madridMidnight)
        XCTAssertEqual(DriveDay.start(of: canaryInstant(16, 12)), madridMidnight)
    }
}
