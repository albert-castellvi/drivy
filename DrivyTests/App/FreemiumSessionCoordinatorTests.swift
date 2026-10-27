import XCTest
@testable import Drivy

/// Lifecycle of the freemium service (S9): created per session, anchored at the
/// account creation date, re-anchored once at the first drive, and dropped on
/// sign-out.
///
/// StoreKit lives behind `PremiumEntitlementProviding` and the service factory is
/// injected, so nothing here touches StoreKit or Supabase.
@MainActor
final class FreemiumSessionCoordinatorTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"
    private static let otherUserID = "99999999-2222-3333-4444-555555555555"

    /// 30 days after the account was created: outside the 7-day window (S9).
    private static let now = PremiumFixtures.date(anchorOffsetDays: 30)

    private static let accountCreatedAt = PremiumFixtures.anchorDate

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: FakePremiumEntitlementProvider!
    private var coordinator: FreemiumSessionCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()

        suiteName = "drivy.tests.freemiumCoordinator.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = FakePremiumEntitlementProvider()

        coordinator = makeCoordinator()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        coordinator = nil
        anchorsBox = nil
        try super.tearDownWithError()
    }

    private func makeCoordinator() -> FreemiumSessionCoordinator {
        let store = self.store!
        let calendar = PremiumFixtures.calendar
        let now = Self.now
        let anchors = AnchorsBox()
        self.anchorsBox = anchors

        return FreemiumSessionCoordinator(
            makeService: { anchor in
                let service = FreemiumService(
                    anchorDate: anchor,
                    store: store,
                    calendar: calendar,
                    now: { now }
                )
                anchors.dates.append(anchor)
                return service
            },
            defaults: defaults,
            now: { now }
        )
    }

    /// Captures the anchors the coordinator built its services with (the factory is
    /// escaping, so it cannot append to a test property directly).
    private final class AnchorsBox {
        var dates: [Date] = []
    }

    private var anchorsBox: AnchorsBox!

    private func user(id: String = FreemiumSessionCoordinatorTests.userID,
                      createdAt: Date? = FreemiumSessionCoordinatorTests.accountCreatedAt) -> UserSummary {
        UserSummary(id: id, email: "ana@example.com", createdAt: createdAt)
    }

    // MARK: - Sign in

    func testServiceDoesNotExistBeforeASession() {
        XCTAssertNil(coordinator.service)
    }

    func testSignInAnchorsTheServiceAtTheAccountCreationDate() async throws {
        await coordinator.signIn(as: user())

        let service = try XCTUnwrap(coordinator.service)
        XCTAssertEqual(anchorsBox.dates, [Self.accountCreatedAt])
        XCTAssertEqual(service.access?.anchorDate, Self.accountCreatedAt)
        XCTAssertEqual(service.state, .free)
        XCTAssertEqual(service.plan, .free)
    }

    func testSignInReadsThePlanAndStartsTheStoreKitListener() async {
        await coordinator.signIn(as: user())

        XCTAssertEqual(store.activeEntitlementsCallCount, 1)
        XCTAssertEqual(store.entitlementUpdatesCallCount, 1)
    }

    func testSignInFallsBackToNowWhenTheSessionHasNoCreationDate() async {
        await coordinator.signIn(as: user(createdAt: nil))

        XCTAssertEqual(anchorsBox.dates, [Self.now])
        XCTAssertEqual(coordinator.service?.access?.anchorDate, Self.now)
    }

    func testSignInAppliesAPremiumEntitlement() async {
        store.entitlements = [PremiumFixtures.entitlement(from: Self.now)]

        await coordinator.signIn(as: user())

        XCTAssertEqual(coordinator.service?.state, .premium)
        XCTAssertEqual(coordinator.service?.plan, .premium)
    }

    func testSigningInTwiceForTheSameUserReusesTheService() async {
        await coordinator.signIn(as: user())
        let first = coordinator.service

        await coordinator.signIn(as: user())

        XCTAssertTrue(coordinator.service === first)
        XCTAssertEqual(anchorsBox.dates.count, 1)
        XCTAssertEqual(store.entitlementUpdatesCallCount, 1)
    }

    func testANewAccountGetsItsOwnService() async {
        await coordinator.signIn(as: user())
        let first = coordinator.service

        await coordinator.signIn(as: user(id: Self.otherUserID, createdAt: nil))

        XCTAssertFalse(coordinator.service === first)
        XCTAssertEqual(anchorsBox.dates.count, 2)
        XCTAssertEqual(anchorsBox.dates.last, Self.now)
    }

    // MARK: - Sign out

    func testSignOutDropsTheServiceAndStopsTheListener() async throws {
        await coordinator.signIn(as: user())
        let service = try XCTUnwrap(coordinator.service)

        coordinator.signOut()

        XCTAssertNil(coordinator.service)

        // A transaction arriving after sign-out must not touch the dropped service.
        store.pushUpdate([PremiumFixtures.entitlement(from: Self.now)])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(service.state, .free)
    }

    // MARK: - First drive anchor (L10)

    func testFirstCompletedDriveMovesTheAnchor() async throws {
        await coordinator.signIn(as: user())
        let service = try XCTUnwrap(coordinator.service)
        XCTAssertEqual(service.access?.anchorDate, Self.accountCreatedAt)

        // 5 days before "now": the 7-day window restarts at the drive.
        let firstDrive = PremiumFixtures.date(anchorOffsetDays: 25)
        coordinator.recordCompletedDrive(startedAt: firstDrive)

        let access = try XCTUnwrap(service.access)
        XCTAssertEqual(access.anchorDate, firstDrive)
        XCTAssertTrue(access.isWithinFullHistoryGrace)
    }

    func testTheAnchorOnlyMovesOnce() async throws {
        await coordinator.signIn(as: user())
        let service = try XCTUnwrap(coordinator.service)
        let firstDrive = PremiumFixtures.date(anchorOffsetDays: 20)

        coordinator.recordCompletedDrive(startedAt: firstDrive)
        coordinator.recordCompletedDrive(startedAt: PremiumFixtures.date(anchorOffsetDays: 25))

        XCTAssertEqual(service.access?.anchorDate, firstDrive)
    }

    func testTheFirstDriveAnchorSurvivesANewSession() async {
        await coordinator.signIn(as: user())
        let firstDrive = PremiumFixtures.date(anchorOffsetDays: 20)
        coordinator.recordCompletedDrive(startedAt: firstDrive)

        coordinator.signOut()
        let reopened = makeCoordinator()
        await reopened.signIn(as: user())

        XCTAssertEqual(reopened.service?.access?.anchorDate, firstDrive)
        XCTAssertEqual(anchorsBox.dates.last, firstDrive)
    }

    func testTheFirstDriveAnchorIsPerAccount() async {
        let firstDrive = PremiumFixtures.date(anchorOffsetDays: 20)
        await coordinator.signIn(as: user())
        coordinator.recordCompletedDrive(startedAt: firstDrive)

        coordinator.signOut()
        let otherAccount = makeCoordinator()
        await otherAccount.signIn(as: user(id: Self.otherUserID, createdAt: nil))

        // The other account keeps its own window: the stored anchor is per user id.
        XCTAssertEqual(otherAccount.service?.access?.anchorDate, Self.now)
    }

    func testFirstDriveAnchorIsIgnoredWithoutASession() {
        coordinator.recordCompletedDrive(startedAt: PremiumFixtures.date(anchorOffsetDays: 20))

        XCTAssertNil(coordinator.service)
    }
}
