import XCTest
@testable import Drivy

/// Entry point other screens use (S9): when the paywall appears and how it is
/// built. Gating wiring itself is out of T5 scope.
@MainActor
final class PaywallPresenterTests: XCTestCase {

    private let now = PremiumFixtures.date(anchorOffsetDays: 8)

    private func makeSUT() -> (sut: PaywallPresenter, service: FreemiumService) {
        let store = FakePremiumEntitlementProvider()
        let clock = now
        let service = FreemiumService(
            anchorDate: PremiumFixtures.anchorDate,
            store: store,
            calendar: PremiumFixtures.calendar,
            now: { clock }
        )
        return (PaywallPresenter(freemium: service), service)
    }

    // MARK: - When to present (S9: after the first completed drive)

    func testPaywallDoesNotAppearBeforeTheFirstDrive() {
        XCTAssertFalse(PaywallPresenter.shouldPresent(completedDriveCount: 0, plan: .free))
    }

    func testPaywallAppearsAfterTheFirstDriveOnTheFreePlan() {
        XCTAssertTrue(PaywallPresenter.shouldPresent(completedDriveCount: 1, plan: .free))
        XCTAssertTrue(PaywallPresenter.shouldPresent(completedDriveCount: 12, plan: .free))
    }

    func testPaywallDoesNotAppearForPremiumUsers() {
        XCTAssertFalse(PaywallPresenter.shouldPresent(completedDriveCount: 1, plan: .premium))
    }

    func testPaywallWaitsWhileThePlanIsStillUnknown() {
        XCTAssertFalse(PaywallPresenter.shouldPresent(completedDriveCount: 1, plan: nil))
    }

    // MARK: - Building the sheet

    func testPresenterBuildsAViewModelForTheSharedService() async {
        let (sut, service) = makeSUT()

        let viewModel = sut.makeViewModel()
        XCTAssertNil(viewModel.plan)

        await service.refresh()
        await viewModel.loadPrice()

        XCTAssertEqual(viewModel.plan, .free)
    }
}
