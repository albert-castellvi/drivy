import XCTest
@testable import Drivy

/// S6, verbatim: "Racha = días consecutivos con ≥ 1 trayecto. La racha se rompe
/// con 2 días sin conducir (gracia de 1 día, estilo Duolingo con 'hielo')".
final class StreakCalculatorTests: XCTestCase {

    /// 2023-11-14T00:00:00Z, a Tuesday.
    private static let today = Date(timeIntervalSince1970: 1_699_920_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Day relative to `today`; 0 is today, -1 yesterday.
    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: Self.today) ?? Self.today
    }

    private func streak(drivingOffsets offsets: [Int]) -> Streak {
        StreakCalculator.streak(
            drivingDays: Set(offsets.map { day($0) }),
            today: Self.today,
            calendar: utc
        )
    }

    // MARK: - The rule

    func testNoDrivesMeansNoStreak() {
        let streak = streak(drivingOffsets: [])

        XCTAssertEqual(streak, .empty)
        XCTAssertEqual(streak.days, 0)
        XCTAssertFalse(streak.isTodayRecorded)
        XCTAssertFalse(streak.usesGraceDay)
    }

    func testConsecutiveDaysAreCounted() {
        let streak = streak(drivingOffsets: [0, -1, -2])

        XCTAssertEqual(streak.days, 3)
        XCTAssertTrue(streak.isTodayRecorded)
        XCTAssertFalse(streak.usesGraceDay)
    }

    /// The user still has the rest of today to drive, so a pending today is not a
    /// gap: the streak stands as it was yesterday.
    func testTodayWithoutADriveKeepsTheRun() {
        let streak = streak(drivingOffsets: [-1, -2])

        XCTAssertEqual(streak.days, 2)
        XCTAssertFalse(streak.isTodayRecorded)
        XCTAssertFalse(streak.usesGraceDay)
        XCTAssertEqual(streak.headline, "2 días de racha")
    }

    /// The grace day ("hielo"): one missing day keeps the run alive and the run
    /// does not count that day.
    func testOneMissingDayIsTheGraceDay() {
        let streak = streak(drivingOffsets: [0, -2, -3])

        XCTAssertEqual(streak.days, 3)
        XCTAssertTrue(streak.usesGraceDay)
        XCTAssertTrue(streak.isTodayRecorded)
    }

    func testTwoConsecutiveMissingDaysBreakTheRun() {
        // Drove today and four days ago: yesterday and the day before are empty,
        // which is the break the spec names.
        let streak = streak(drivingOffsets: [0, -3, -4])

        XCTAssertEqual(streak.days, 1)
        XCTAssertFalse(streak.usesGraceDay)
        XCTAssertTrue(streak.isTodayRecorded)
    }

    func testBrokenRunShowsNothingEvenWithAnOlderStreak() {
        // Nothing today or yesterday, and the day before is empty too: the older
        // run must not be reported as the current streak.
        let streak = streak(drivingOffsets: [-3])

        XCTAssertEqual(streak.days, 0)
        XCTAssertFalse(streak.isTodayRecorded)
    }

    func testTimeOfDayIsIgnored() {
        let lateDrive = day(0).addingTimeInterval(23 * 3600 + 59 * 60)
        let earlyDrive = day(-1).addingTimeInterval(60)

        let streak = StreakCalculator.streak(
            drivingDays: [lateDrive, earlyDrive],
            today: Self.today,
            calendar: utc
        )

        XCTAssertEqual(streak.days, 2)
        XCTAssertTrue(streak.isTodayRecorded)
    }

    // MARK: - Copy shown by the racha card

    func testHeadlineUsesSingularForOneDay() {
        XCTAssertEqual(streak(drivingOffsets: [0]).headline, "1 día de racha")
    }

    func testZeroStreakHeadline() {
        XCTAssertEqual(streak(drivingOffsets: []).headline, "Sin racha")
    }

    func testDetailAnnouncesTheSpentGraceDay() {
        XCTAssertEqual(
            streak(drivingOffsets: [0, -2]).detail,
            "Has usado tu día de gracia: dos días sin conducir y la racha se rompe."
        )
    }

    func testDetailAsksForTodaysDriveWhenTodayIsPending() {
        XCTAssertEqual(
            streak(drivingOffsets: [-1]).detail,
            "Conduce hoy para mantenerla. Un día sin conducir no la rompe."
        )
    }

    func testDetailOfAnActiveDayWithTheGraceAvailable() {
        XCTAssertEqual(
            streak(drivingOffsets: [0, -1]).detail,
            "Hoy ya cuenta. Un día sin conducir no la rompe."
        )
    }

    func testZeroStreakDetailInvitesTheFirstDrive() {
        XCTAssertEqual(
            streak(drivingOffsets: []).detail,
            "Registra tu primer trayecto para empezar la racha."
        )
    }
}
