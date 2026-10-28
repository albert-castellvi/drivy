import XCTest
@testable import Drivy

/// S7, "nunca durante un trayecto" (B2 of the QA report): a drive start withdraws
/// both notifications of the day, and the repeating Monday league results are not
/// scheduled again until the drive is over.
final class NotificationPolicyTests: XCTestCase {

    func testADriveStartWithdrawsBothNotificationsOfTheDay() {
        XCTAssertEqual(
            NotificationPolicy.suppressedWhileDriving,
            ["drivy.streak.reminder", "drivy.league.results"]
        )
    }

    func testTheLeagueResultsAreNotScheduledWhileDriving() {
        XCTAssertFalse(
            NotificationPolicy.schedulesLeagueResults(isDriving: true, isInPublicLeagues: true)
        )
    }

    func testTheLeagueResultsComeBackWhenTheDriveEnds() {
        XCTAssertTrue(
            NotificationPolicy.schedulesLeagueResults(isDriving: false, isInPublicLeagues: true)
        )
    }

    func testTheLeagueResultsNeedTheOptIn() {
        XCTAssertFalse(
            NotificationPolicy.schedulesLeagueResults(isDriving: false, isInPublicLeagues: false)
        )
        XCTAssertFalse(
            NotificationPolicy.schedulesLeagueResults(isDriving: true, isInPublicLeagues: false)
        )
    }
}
