import XCTest
@testable import Drivy

/// Purchase/restore flow of the paywall (S9), asserted through the exact
/// Spanish copy the user sees.
@MainActor
final class PaywallViewModelTests: XCTestCase {

    private let now = PremiumFixtures.date(anchorOffsetDays: 8)

    private func makeSUT() -> (
        sut: PaywallViewModel,
        service: FreemiumService,
        store: FakePremiumEntitlementProvider
    ) {
        let store = FakePremiumEntitlementProvider()
        let clock = now
        let service = FreemiumService(
            anchorDate: PremiumFixtures.anchorDate,
            store: store,
            calendar: PremiumFixtures.calendar,
            now: { clock }
        )
        return (PaywallViewModel(freemium: service), service, store)
    }

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

    func testInitialStateShowsTheFallbackPrice() {
        let (sut, _, _) = makeSUT()

        XCTAssertEqual(sut.status, .idle)
        XCTAssertEqual(sut.priceText, PremiumProduct.fallbackPriceText)
        XCTAssertNil(sut.plan)
        XCTAssertFalse(sut.isBusy)
        XCTAssertEqual(sut.benefits, PaywallCopy.benefits)
    }

    // MARK: - Price

    func testLoadPriceUsesTheStorefrontPrice() async {
        let (sut, _, store) = makeSUT()
        store.displayPrice = "4,99 €"

        await sut.loadPrice()

        XCTAssertEqual(sut.priceText, "4,99 €/mes")
        XCTAssertEqual(sut.status, .idle)
    }

    func testLoadPriceKeepsTheFallbackWhenStoreKitCannotAnswer() async {
        let (sut, _, store) = makeSUT()
        store.displayPrice = nil

        await sut.loadPrice()

        XCTAssertEqual(sut.priceText, PremiumProduct.fallbackPriceText)
    }

    func testLoadPriceQueriesStoreKitOnlyOnce() async {
        let (sut, _, store) = makeSUT()

        await sut.loadPrice()
        await sut.loadPrice()

        XCTAssertEqual(store.displayPriceCallCount, 1)
    }

    func testLoadPricePicksUpAnAlreadyPremiumPlan() async {
        let (sut, service, store) = makeSUT()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        await service.refresh()

        await sut.loadPrice()

        XCTAssertEqual(sut.plan, .premium)
    }

    // MARK: - Purchase

    func testPurchaseUnlocksPremium() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.purchaseResult = .success([PremiumFixtures.entitlement(from: now)])

        await sut.purchase()

        XCTAssertEqual(store.purchaseCallCount, 1)
        XCTAssertEqual(sut.status, .purchased)
        XCTAssertEqual(sut.plan, .premium)
        XCTAssertEqual(service.state, .premium)
    }

    func testPurchaseCancellationReturnsToIdleWithoutError() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.purchaseResult = .failure(PaywallError.cancelled)

        await sut.purchase()

        XCTAssertEqual(sut.status, .idle)
        XCTAssertEqual(sut.plan, .free)
    }

    func testPendingPurchaseShowsTheExactMessage() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.purchaseResult = .failure(PaywallError.pending)

        await sut.purchase()

        XCTAssertEqual(
            sut.status,
            .failed("Tu compra está pendiente de aprobación. Te avisaremos cuando se complete.")
        )
        XCTAssertEqual(sut.plan, .free)
    }

    func testNetworkFailureShowsTheExactMessage() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.purchaseResult = .failure(PaywallError.network)

        await sut.purchase()

        XCTAssertEqual(
            sut.status,
            .failed("No hay conexión. Comprueba tu red e inténtalo de nuevo.")
        )
    }

    func testNonPaywallErrorFallsBackToTheGenericMessage() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.purchaseResult = .failure(FakePremiumEntitlementProvider.FakeError.boom)

        await sut.purchase()

        XCTAssertEqual(sut.status, .failed(PaywallCopy.genericErrorMessage))
    }

    func testPurchaseIsIgnoredWhileOneIsAlreadyInFlight() async throws {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.suspendsPurchase = true
        store.purchaseResult = .success([PremiumFixtures.entitlement(from: now)])

        let firstPurchase = Task { await sut.purchase() }
        try await waitUntil { sut.status == .purchasing }

        await sut.purchase()
        XCTAssertEqual(store.purchaseCallCount, 1)
        XCTAssertTrue(sut.isBusy)

        store.resumePurchase()
        await firstPurchase.value

        XCTAssertEqual(sut.status, .purchased)
        XCTAssertEqual(sut.plan, .premium)
    }

    // MARK: - Restore

    func testRestoreUnlocksPremium() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.restoreResult = .success([PremiumFixtures.entitlement(from: now)])

        await sut.restore()

        XCTAssertEqual(store.restoreCallCount, 1)
        XCTAssertEqual(sut.status, .purchased)
        XCTAssertEqual(sut.plan, .premium)
    }

    func testRestoreWithoutPurchasesExplainsNothingWasFound() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.restoreResult = .success([])

        await sut.restore()

        XCTAssertEqual(sut.status, .failed(PaywallCopy.restoreNothingFoundMessage))
        XCTAssertEqual(sut.plan, .free)
    }

    func testRestoreFailureShowsTheExactMessage() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.restoreResult = .failure(PaywallError.storeUnavailable)

        await sut.restore()

        XCTAssertEqual(
            sut.status,
            .failed("App Store no está disponible ahora mismo. Inténtalo más tarde.")
        )
    }

    func testRestoreCancellationReturnsToIdleWithoutError() async {
        let (sut, service, store) = makeSUT()
        await service.refresh()
        store.restoreResult = .failure(PaywallError.cancelled)

        await sut.restore()

        XCTAssertEqual(sut.status, .idle)
    }
}
