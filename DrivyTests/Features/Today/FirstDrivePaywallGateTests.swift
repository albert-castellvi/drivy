import XCTest
@testable import Drivy

/// S9: the paywall appears after the first completed drive, and only once ever.
///
/// The gate is presentation state only: it never runs before the drive is recorded
/// and it never blocks one.
@MainActor
final class FirstDrivePaywallGateTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var gate: FirstDrivePaywallGate!

    override func setUpWithError() throws {
        try super.setUpWithError()

        suiteName = "drivy.tests.paywallGate.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        gate = FirstDrivePaywallGate(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        gate = nil
        try super.tearDownWithError()
    }

    // MARK: - When it is due

    func testNothingIsPresentedBeforeTheFirstDrive() {
        XCTAssertFalse(gate.shouldPresent(completedDriveCount: 0, plan: .free))
        XCTAssertFalse(gate.wasPresented)
    }

    func testTheFirstDriveOnTheFreePlanPresentsThePaywall() {
        XCTAssertTrue(gate.shouldPresent(completedDriveCount: 1, plan: .free))
    }

    func testAPremiumPlanIsNeverAskedForThePaywall() {
        XCTAssertFalse(gate.shouldPresent(completedDriveCount: 1, plan: .premium))
        XCTAssertFalse(gate.wasPresented)
    }

    /// While the plan is unknown S9 is not satisfied yet, so the gate must not burn
    /// its one chance.
    func testAnUnknownPlanKeepsThePaywallDue() {
        XCTAssertFalse(gate.shouldPresent(completedDriveCount: 1, plan: nil))
        XCTAssertFalse(gate.wasPresented)

        XCTAssertTrue(gate.shouldPresent(completedDriveCount: 1, plan: .free))
    }

    // MARK: - Once ever

    func testItIsPresentedOnlyOnce() {
        XCTAssertTrue(gate.shouldPresent(completedDriveCount: 1, plan: .free))
        gate.markPresented()

        XCTAssertFalse(gate.shouldPresent(completedDriveCount: 1, plan: .free))
        // Later drives of the same session do not bring it back either.
        XCTAssertFalse(gate.shouldPresent(completedDriveCount: 4, plan: .free))
    }

    func testTheFlagSurvivesTheNextLaunch() {
        gate.markPresented()

        let reopened = FirstDrivePaywallGate(defaults: defaults)

        XCTAssertTrue(reopened.wasPresented)
        XCTAssertFalse(reopened.shouldPresent(completedDriveCount: 1, plan: .free))
    }
}
