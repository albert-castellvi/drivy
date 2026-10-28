import XCTest
@testable import Drivy

/// S7: the reminder invites to the lesson at 20:00, skips a day that already
/// counts and is never pending while driving.
final class ReminderScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    func testTodayAtEightWhenTheDayDoesNotCountYet() {
        let fire = ReminderSchedule.nextFireDate(
            now: date(27, 9), todayCounted: false, isDriving: false, calendar: calendar
        )

        XCTAssertEqual(fire, date(27, 20))
    }

    func testTomorrowWhenTodayAlreadyCounts() {
        let fire = ReminderSchedule.nextFireDate(
            now: date(27, 9), todayCounted: true, isDriving: false, calendar: calendar
        )

        XCTAssertEqual(fire, date(28, 20))
    }

    func testTomorrowWhenEightIsAlreadyPast() {
        let fire = ReminderSchedule.nextFireDate(
            now: date(27, 20, 30), todayCounted: false, isDriving: false, calendar: calendar
        )

        XCTAssertEqual(fire, date(28, 20))
    }

    func testNothingWhileDriving() {
        let fire = ReminderSchedule.nextFireDate(
            now: date(27, 9), todayCounted: false, isDriving: true, calendar: calendar
        )

        XCTAssertNil(fire)
    }
}
