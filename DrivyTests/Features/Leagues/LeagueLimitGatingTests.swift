import XCTest
@testable import Drivy

/// S9 league cap: the free plan allows one league, so creating or joining a second
/// one is refused before the backend is touched, and the refusal carries the paywall
/// copy.
///
/// The gateway is asserted directly, and the view model is asserted through its public
/// interface (`createLeague` / `joinLeague`) with the fake Supabase boundary.
@MainActor
final class LeagueLimitGatingTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"

    private static let league = LeagueRecord(
        id: "1c2d3e4f-1111-4222-8333-944455556666",
        name: "Los del barrio",
        ownerID: LeagueLimitGatingTests.userID,
        inviteCode: "ABC234"
    )

    private static let anchorDate = PremiumFixtures.anchorDate

    private func access(plan: FreemiumPlan) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: Self.anchorDate,
            now: PremiumFixtures.date(anchorOffsetDays: 2),
            calendar: PremiumFixtures.calendar
        )
    }

    private func makeSUT(
        leagues: [LeagueRecord] = []
    ) async -> (sut: LeaguesViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        fake.leaguesResult = .success(leagues)
        fake.createOutcome = .success(Self.league)
        fake.joinOutcome = .success(Self.league.id)

        let sut = LeaguesViewModel(repository: fake, inviteCodeGenerator: { "XYZ789" })
        await sut.load(userID: Self.userID)
        return (sut, fake)
    }

    // MARK: - The rule

    func testAFreeAccountWithOneLeagueIsAtTheLimit() {
        XCTAssertTrue(LeagueLimitGate.isAtLimit(access: access(plan: .free), leagueCount: 1))
        XCTAssertTrue(LeagueLimitGate.isAtLimit(access: access(plan: .free), leagueCount: 2))
    }

    func testAFreeAccountWithoutLeaguesIsNotAtTheLimit() {
        XCTAssertFalse(LeagueLimitGate.isAtLimit(access: access(plan: .free), leagueCount: 0))
    }

    func testAPremiumAccountIsNeverAtTheLimit() {
        XCTAssertFalse(LeagueLimitGate.isAtLimit(access: access(plan: .premium), leagueCount: 5))
    }

    /// A plan that could not be read must never lock the user out (S9/S12).
    func testAnUnknownPlanGatesNothing() {
        XCTAssertFalse(LeagueLimitGate.isAtLimit(access: nil, leagueCount: 5))
    }

    func testTheLimitUsesThePaywallCopy() {
        XCTAssertEqual(LeagueLimitGate.limitMessage, PaywallCopy.leagueLimitMessage)
        XCTAssertEqual(
            LeagueLimitGate.limitMessage,
            "El plan Free permite 1 liga. Hazte Premium para crear o unirte a más."
        )
    }

    // MARK: - Create

    func testCreatingASecondLeagueIsRefusedOnTheFreePlan() async {
        let (sut, fake) = await makeSUT(leagues: [Self.league])
        XCTAssertTrue(sut.isLeagueLimitReached(access: access(plan: .free)))

        let created = await sut.createLeague(
            name: "Otra liga",
            userID: Self.userID,
            access: access(plan: .free)
        )

        XCTAssertFalse(created)
        XCTAssertTrue(fake.createCalls.isEmpty)
        XCTAssertEqual(sut.createErrorMessage, PaywallCopy.leagueLimitMessage)
        XCTAssertEqual(sut.leagues, [Self.league])
    }

    func testCreatingTheFirstLeagueIsAllowedOnTheFreePlan() async {
        let (sut, fake) = await makeSUT()

        let created = await sut.createLeague(
            name: "Los del barrio",
            userID: Self.userID,
            access: access(plan: .free)
        )

        XCTAssertTrue(created)
        XCTAssertEqual(fake.createCalls.count, 1)
        XCTAssertNil(sut.createErrorMessage)
    }

    func testAPremiumAccountCanCreateAnotherLeague() async {
        let (sut, fake) = await makeSUT(leagues: [Self.league])

        let created = await sut.createLeague(
            name: "Otra liga",
            userID: Self.userID,
            access: access(plan: .premium)
        )

        XCTAssertTrue(created)
        XCTAssertEqual(fake.createCalls.count, 1)
    }

    // MARK: - Join

    func testJoiningASecondLeagueIsRefusedOnTheFreePlan() async {
        let (sut, fake) = await makeSUT(leagues: [Self.league])

        let joined = await sut.joinLeague(
            code: "ABC234",
            userID: Self.userID,
            access: access(plan: .free)
        )

        XCTAssertFalse(joined)
        XCTAssertTrue(fake.joinCalls.isEmpty)
        XCTAssertEqual(sut.joinErrorMessage, PaywallCopy.leagueLimitMessage)
    }

    func testJoiningTheFirstLeagueIsAllowedOnTheFreePlan() async {
        let (sut, fake) = await makeSUT()

        let joined = await sut.joinLeague(
            code: "ABC234",
            userID: Self.userID,
            access: access(plan: .free)
        )

        XCTAssertTrue(joined)
        XCTAssertEqual(fake.joinCalls, ["ABC234"])
    }

    /// Preserved behaviour: without a plan snapshot the view model behaves exactly as
    /// before the gating existed.
    func testWithoutAPlanSnapshotTheViewModelDoesNotGate() async {
        let (sut, fake) = await makeSUT(leagues: [Self.league])

        let created = await sut.createLeague(name: "Otra liga", userID: Self.userID)

        XCTAssertTrue(created)
        XCTAssertEqual(fake.createCalls.count, 1)
    }
}
