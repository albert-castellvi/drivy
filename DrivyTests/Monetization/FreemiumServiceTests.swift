import XCTest
@testable import Drivy

/// Freemium state machine of S9: unknown → loading → free/premium, plus the
/// purchase, restore and `Transaction.updates` paths.
///
/// StoreKit lives behind `PremiumEntitlementProviding`, so no test here touches
/// StoreKit and CI needs no StoreKitTest session.
@MainActor
final class FreemiumServiceTests: XCTestCase {

    private let now = PremiumFixtures.date(anchorOffsetDays: 8)

    private func makeSUT() -> (sut: FreemiumService, store: FakePremiumEntitlementProvider) {
        let store = FakePremiumEntitlementProvider()
        let clock = now
        let sut = FreemiumService(
            anchorDate: PremiumFixtures.anchorDate,
            store: store,
            calendar: PremiumFixtures.calendar,
            now: { clock }
        )
        return (sut, store)
    }

    /// Polls until `condition` holds, so listener-driven transitions can be
    /// asserted without sleeping for an arbitrary amount of time.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not reached within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Initial state

    func testStateStartsAsUnknown() {
        let (sut, _) = makeSUT()

        XCTAssertEqual(sut.state, .unknown)
        XCTAssertNil(sut.plan)
        XCTAssertNil(sut.access)
        XCTAssertFalse(sut.isPremium)
    }

    // MARK: - Refresh

    func testRefreshMovesToFreeWhenThereIsNoEntitlement() async {
        let (sut, store) = makeSUT()

        await sut.refresh()

        XCTAssertEqual(store.activeEntitlementsCallCount, 1)
        XCTAssertEqual(sut.state, .free)
        XCTAssertEqual(sut.plan, .free)
        XCTAssertEqual(sut.access?.plan, .free)
        XCTAssertFalse(sut.isPremium)
    }

    func testRefreshMovesToPremiumWithAnActiveEntitlement() async {
        let (sut, store) = makeSUT()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]

        await sut.refresh()

        XCTAssertEqual(sut.state, .premium)
        XCTAssertEqual(sut.plan, .premium)
        XCTAssertEqual(sut.access?.plan, .premium)
        XCTAssertTrue(sut.isPremium)
    }

    func testRefreshIgnoresAnExpiredEntitlement() async {
        let (sut, store) = makeSUT()
        store.entitlements = [PremiumFixtures.entitlement(expiringIn: -1, from: now)]

        await sut.refresh()

        XCTAssertEqual(sut.state, .free)
    }

    func testRefreshIgnoresARevokedEntitlement() async {
        let (sut, store) = makeSUT()
        store.entitlements = [
            PremiumEntitlement(
                productID: PremiumProduct.monthlyIdentifier,
                expirationDate: now.addingTimeInterval(86_400),
                revocationDate: now
            )
        ]

        await sut.refresh()

        XCTAssertEqual(sut.state, .free)
    }

    func testRefreshBuildsTheAccessSnapshotFromTheInjectedClock() async {
        let (sut, _) = makeSUT()

        await sut.refresh()

        XCTAssertEqual(sut.access?.now, now)
        XCTAssertEqual(sut.access?.anchorDate, PremiumFixtures.anchorDate)
        XCTAssertEqual(sut.access?.daysSinceAnchor, 8)
        XCTAssertEqual(sut.access?.canViewHistory(date: now), true)
        XCTAssertEqual(
            sut.access?.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)),
            false
        )
    }

    func testRefreshCanBeCalledTwiceAndKeepsTheLatestEntitlement() async {
        let (sut, store) = makeSUT()

        await sut.refresh()
        XCTAssertEqual(sut.state, .free)

        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        await sut.refresh()

        XCTAssertEqual(store.activeEntitlementsCallCount, 2)
        XCTAssertEqual(sut.state, .premium)
    }

    // MARK: - Purchase

    func testPurchaseAppliesPremium() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.purchaseResult = .success([PremiumFixtures.entitlement(from: now)])

        let plan = try await sut.purchase()

        XCTAssertEqual(store.purchaseCallCount, 1)
        XCTAssertEqual(plan, .premium)
        XCTAssertEqual(sut.state, .premium)
        XCTAssertTrue(sut.isPremium)
    }

    func testPurchaseCancellationKeepsTheFreePlanAndRethrows() async {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.purchaseResult = .failure(PaywallError.cancelled)

        do {
            _ = try await sut.purchase()
            XCTFail("A cancelled purchase must throw")
        } catch {
            XCTAssertEqual(error as? PaywallError, .cancelled)
        }

        XCTAssertEqual(sut.state, .free)
        XCTAssertFalse(sut.isPremium)
    }

    func testPurchaseFailureBeforeAnyRefreshKeepsUnknown() async {
        let (sut, store) = makeSUT()
        store.purchaseResult = .failure(PaywallError.network)

        do {
            _ = try await sut.purchase()
            XCTFail("A failed purchase must throw")
        } catch {
            XCTAssertEqual(error as? PaywallError, .network)
        }

        XCTAssertEqual(sut.state, .unknown)
    }

    func testPurchaseWithoutAnEntitlementStaysFree() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.purchaseResult = .success([])

        let plan = try await sut.purchase()

        XCTAssertEqual(plan, .free)
        XCTAssertEqual(sut.state, .free)
    }

    // MARK: - Restore

    func testRestoreAppliesPremium() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.restoreResult = .success([PremiumFixtures.entitlement(from: now)])

        let plan = try await sut.restore()

        XCTAssertEqual(store.restoreCallCount, 1)
        XCTAssertEqual(plan, .premium)
        XCTAssertEqual(sut.state, .premium)
    }

    func testRestoreWithoutPurchasesKeepsFree() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.restoreResult = .success([])

        let plan = try await sut.restore()

        XCTAssertEqual(plan, .free)
        XCTAssertEqual(sut.state, .free)
    }

    func testRestoreFailureRethrowsAndKeepsThePlan() async {
        let (sut, store) = makeSUT()
        await sut.refresh()
        store.restoreResult = .failure(PaywallError.storeUnavailable)

        do {
            _ = try await sut.restore()
            XCTFail("A failed restore must throw")
        } catch {
            XCTAssertEqual(error as? PaywallError, .storeUnavailable)
        }

        XCTAssertEqual(sut.state, .free)
    }

    // MARK: - Transaction listener (S9)

    func testEntitlementUpdatesUpgradeToPremium() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()

        sut.startObservingEntitlementUpdates()
        XCTAssertEqual(store.entitlementUpdatesCallCount, 1)

        store.pushUpdate([PremiumFixtures.entitlement(from: now)])
        try await waitUntil { sut.state == .premium }

        XCTAssertEqual(sut.plan, .premium)
    }

    func testEntitlementUpdatesDowngradeToFreeWhenTheSubscriptionLapses() async throws {
        let (sut, store) = makeSUT()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        await sut.refresh()
        XCTAssertEqual(sut.state, .premium)

        sut.startObservingEntitlementUpdates()
        store.pushUpdate([])
        try await waitUntil { sut.state == .free }

        XCTAssertFalse(sut.isPremium)
    }

    func testStartingTheListenerTwiceSubscribesOnce() async {
        let (sut, store) = makeSUT()

        sut.startObservingEntitlementUpdates()
        sut.startObservingEntitlementUpdates()

        XCTAssertEqual(store.entitlementUpdatesCallCount, 1)
    }

    func testStoppingTheListenerIgnoresFurtherUpdates() async throws {
        let (sut, store) = makeSUT()
        await sut.refresh()
        sut.startObservingEntitlementUpdates()
        sut.stopObservingEntitlementUpdates()

        store.pushUpdate([PremiumFixtures.entitlement(from: now)])
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(sut.state, .free)
    }

    func testRestartingTheListenerSubscribesAgain() async {
        let (sut, store) = makeSUT()

        sut.startObservingEntitlementUpdates()
        sut.stopObservingEntitlementUpdates()
        sut.startObservingEntitlementUpdates()

        XCTAssertEqual(store.entitlementUpdatesCallCount, 2)
    }

    // MARK: - Anchor date (profile / first drive date)

    func testUpdatingTheAnchorDateRecomputesTheFreeAccess() async {
        let (sut, _) = makeSUT()
        await sut.refresh()

        XCTAssertFalse(
            sut.access?.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)) ?? true
        )

        // The parent re-anchors the window once the first drive is uploaded.
        sut.updateAnchorDate(PremiumFixtures.date(anchorOffsetDays: 7))

        XCTAssertTrue(
            sut.access?.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)) ?? false
        )
        XCTAssertEqual(sut.access?.daysSinceAnchor, 1)
    }

    func testUpdatingTheAnchorDateBeforeAnyRefreshKeepsUnknown() {
        let (sut, _) = makeSUT()

        sut.updateAnchorDate(PremiumFixtures.date(anchorOffsetDays: 7))

        XCTAssertEqual(sut.state, .unknown)
        XCTAssertNil(sut.access)
    }

    func testUpdatingTheAnchorDateDoesNotChangeAPremiumPlan() async {
        let (sut, store) = makeSUT()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        await sut.refresh()

        sut.updateAnchorDate(PremiumFixtures.date(anchorOffsetDays: 7))

        XCTAssertEqual(sut.state, .premium)
        XCTAssertTrue(
            sut.access?.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: -100)) ?? false
        )
    }

    // MARK: - Price

    func testPremiumDisplayPriceComesFromTheStore() async {
        let (sut, store) = makeSUT()
        store.displayPrice = "4,99 €"

        let price = await sut.premiumDisplayPrice()

        XCTAssertEqual(price, "4,99 €")
        XCTAssertEqual(store.displayPriceCallCount, 1)
    }
}
