import XCTest
@testable import Drivy

/// Server verification of the premium entitlement (S5.3): the JWS selection
/// rule, the per-session dedupe and the failure swallowing of `PremiumSync`,
/// plus the `FreemiumService` hooks that post at launch and on
/// `Transaction.updates`.
///
/// No test touches StoreKit or the network: the JWS selection is a pure
/// function over `PremiumEntitlement` values, and both sync boundaries are
/// protocol-backed doubles.
@MainActor
final class PremiumSyncTests: XCTestCase {

    private let now = PremiumFixtures.date(anchorOffsetDays: 8)

    // MARK: - Doubles

    /// Endpoint double: records the posted JWSs, optionally throws.
    private final class SpyEndpoint: PremiumSyncEndpoint {

        enum FakeError: Error { case rejected }

        var error: Error?

        private(set) var posted: [String] = []

        func verify(jws: String) async throws {
            posted.append(jws)
            if let error { throw error }
        }
    }

    /// Sync double for the `FreemiumService` hook tests.
    private final class SpySync: PremiumSyncing {

        private(set) var posted: [String] = []

        func post(jws: String) async {
            posted.append(jws)
        }
    }

    private func makeSync(error: Error? = nil) -> (sync: PremiumSync, endpoint: SpyEndpoint) {
        let endpoint = SpyEndpoint()
        endpoint.error = error
        return (PremiumSync(endpoint: endpoint), endpoint)
    }

    /// Polls until `condition` holds, so hooks that run in a background task
    /// can be asserted without sleeping for an arbitrary amount of time.
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

    private func makeService(
        store: FakePremiumEntitlementProvider,
        sync: PremiumSyncing?
    ) -> FreemiumService {
        let clock = now
        return FreemiumService(
            anchorDate: PremiumFixtures.anchorDate,
            store: store,
            calendar: PremiumFixtures.calendar,
            now: { clock },
            premiumSync: sync
        )
    }

    // MARK: - JWS of the verified current entitlement only

    func testActivePremiumEntitlementExposesItsJWS() {
        let jws = PremiumEntitlement.verifiedCurrentJWS(
            in: [PremiumFixtures.entitlement(jws: "jws-1")],
            at: now
        )

        XCTAssertEqual(jws, "jws-1")
    }

    func testExpiredEntitlementExposesNoJWS() {
        let expired = PremiumEntitlement(
            productID: PremiumProduct.monthlyIdentifier,
            expirationDate: now.addingTimeInterval(-86_400),
            jws: "jws-expired"
        )

        XCTAssertNil(PremiumEntitlement.verifiedCurrentJWS(in: [expired], at: now))
    }

    func testRevokedEntitlementExposesNoJWS() {
        let revoked = PremiumEntitlement(
            productID: PremiumProduct.monthlyIdentifier,
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: now.addingTimeInterval(-3_600),
            jws: "jws-revoked"
        )

        XCTAssertNil(PremiumEntitlement.verifiedCurrentJWS(in: [revoked], at: now))
    }

    func testForeignProductEntitlementExposesNoJWS() {
        let other = PremiumEntitlement(
            productID: "com.acrstudio.drivy.other",
            expirationDate: now.addingTimeInterval(86_400),
            jws: "jws-other"
        )

        XCTAssertNil(PremiumEntitlement.verifiedCurrentJWS(in: [other], at: now))
    }

    func testAnEntitlementWithoutJWSIsSkippedAndTheNextCurrentOneWins() {
        let withoutJWS = PremiumFixtures.entitlement()
        let current = PremiumFixtures.entitlement(jws: "jws-current")

        let jws = PremiumEntitlement.verifiedCurrentJWS(
            in: [withoutJWS, current],
            at: now
        )

        XCTAssertEqual(jws, "jws-current")
    }

    func testNoEntitlementsExposesNoJWS() {
        XCTAssertNil(PremiumEntitlement.verifiedCurrentJWS(in: [], at: now))
    }

    // MARK: - PremiumSync: one post per JWS, failures swallowed

    func testPostSendsTheExactJWS() async {
        let (sync, endpoint) = makeSync()

        await sync.post(jws: "jws-1")

        XCTAssertEqual(endpoint.posted, ["jws-1"])
    }

    func testTheSameJWSIsPostedOnlyOncePerSession() async {
        let (sync, endpoint) = makeSync()

        await sync.post(jws: "jws-1")
        await sync.post(jws: "jws-1")
        await sync.post(jws: "jws-1")

        XCTAssertEqual(endpoint.posted, ["jws-1"])
    }

    func testADifferentJWSIsPostedAgain() async {
        let (sync, endpoint) = makeSync()

        await sync.post(jws: "jws-1")
        await sync.post(jws: "jws-2")

        XCTAssertEqual(endpoint.posted, ["jws-1", "jws-2"])
    }

    func testAFailedPostDoesNotThrowAndIsNotRetriedForTheSameJWS() async {
        let (sync, endpoint) = makeSync(error: SpyEndpoint.FakeError.rejected)

        await sync.post(jws: "jws-1")
        // A second read of the same entitlement must not repost it either.
        await sync.post(jws: "jws-1")

        XCTAssertEqual(endpoint.posted, ["jws-1"])
    }

    // MARK: - FreemiumService hooks

    func testRefreshPostsTheProvidersJWS() async throws {
        let store = FakePremiumEntitlementProvider()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        store.verifiedJWS = "jws-launch"
        let spy = SpySync()
        let sut = makeService(store: store, sync: spy)

        await sut.refresh()

        try await waitUntil { spy.posted == ["jws-launch"] }
    }

    func testAnEntitlementUpdatePostsTheNewJWS() async throws {
        let store = FakePremiumEntitlementProvider()
        let spy = SpySync()
        let sut = makeService(store: store, sync: spy)
        sut.startObservingEntitlementUpdates()

        store.verifiedJWS = "jws-update"
        store.pushUpdate([PremiumFixtures.entitlement(from: now)])
        try await waitUntil { spy.posted == ["jws-update"] }

        sut.stopObservingEntitlementUpdates()
    }

    func testNoCurrentJWSPostsNothing() async throws {
        let store = FakePremiumEntitlementProvider()
        store.entitlements = [PremiumFixtures.entitlement(from: now)]
        let spy = SpySync()
        let sut = makeService(store: store, sync: spy)

        await sut.refresh()

        // Give the scheduled hook a chance to run before asserting.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(spy.posted.isEmpty)
    }

    func testAFreePlanPostsNothing() async throws {
        let store = FakePremiumEntitlementProvider()
        store.verifiedJWS = "jws-should-never-post"
        let spy = SpySync()
        let sut = makeService(store: store, sync: spy)

        await sut.refresh()

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(spy.posted.isEmpty)
    }
}
