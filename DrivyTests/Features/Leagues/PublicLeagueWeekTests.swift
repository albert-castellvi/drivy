import XCTest
@testable import Drivy

/// The week of the public leagues (S5, L8): groups are formed on Monday 00:00
/// Europe/Madrid, and the screen counts the days left until the next Monday.
final class PublicLeagueWeekTests: XCTestCase {

    private var madrid: Calendar { PublicLeagueWeek.madridCalendar }

    /// A moment of the Madrid calendar, so the test never depends on the zone of
    /// the machine that runs it.
    private func moment(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        guard let date = madrid.date(from: components) else {
            XCTFail("Invalid Madrid date")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    // MARK: - Week key

    func testTheWeekKeyIsTheMadridMonday() {
        XCTAssertEqual(PublicLeagueWeek.weekStartKey(for: moment(2023, 11, 13)), "2023-11-13")
        XCTAssertEqual(PublicLeagueWeek.weekStartKey(for: moment(2023, 11, 15)), "2023-11-13")
    }

    func testSundayNightStillBelongsToTheWeekThatStartedOnMonday() {
        let sunday = moment(2023, 11, 19, 23, 30)

        XCTAssertEqual(PublicLeagueWeek.weekStartKey(for: sunday), "2023-11-13")
    }

    // MARK: - Days left

    func testMondayJustAfterMidnightHasTheWholeWeekAhead() {
        let days = PublicLeagueWeek.daysLeft(now: moment(2023, 11, 13, 0, 1))

        XCTAssertEqual(days, 7)
    }

    func testTheDaysLeftCountTheRemainingCalendarDays() {
        let days = PublicLeagueWeek.daysLeft(now: moment(2023, 11, 15))

        XCTAssertEqual(days, 5)
    }

    func testTheLastDayOfTheWeekHasOneDayLeft() {
        let days = PublicLeagueWeek.daysLeft(now: moment(2023, 11, 19, 23, 59))

        XCTAssertEqual(days, 1)
    }

    func testTheCountdownSurvivesTheChangeToSummerTime() {
        // Madrid moves the clock on Sunday 2024-03-31, inside the week that
        // started on Monday 2024-03-25.
        XCTAssertEqual(PublicLeagueWeek.weekStartKey(for: moment(2024, 3, 27)), "2024-03-25")
        XCTAssertEqual(PublicLeagueWeek.daysLeft(now: moment(2024, 3, 27)), 5)
    }

    // MARK: - Copy

    func testTheLastDayUsesTheSingular() {
        XCTAssertEqual(PublicLeagueWeek.daysLeftText(1), "Queda 1 día de liga")
    }

    func testMoreThanOneDayUsesThePlural() {
        XCTAssertEqual(PublicLeagueWeek.daysLeftText(4), "Quedan 4 días de liga")
        XCTAssertEqual(PublicLeagueWeek.daysLeftText(7), "Quedan 7 días de liga")
    }
}
