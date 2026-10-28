import XCTest
@testable import Drivy

/// The public league block of the Ligas tab (S5, L9): the invitation while the
/// user never decided, the group of the week once opted in, and the opt-out.
@MainActor
final class PublicLeagueViewModelTests: XCTestCase {

    /// Wednesday 2023-11-15 12:00 Europe/Madrid, i.e. the week of 2023-11-13.
    private static let now: Date = {
        var components = DateComponents()
        components.year = 2023
        components.month = 11
        components.day = 15
        components.hour = 12
        return PublicLeagueWeek.madridCalendar.date(from: components)
            ?? Date(timeIntervalSince1970: 0)
    }()

    private static let groupID = "9a8b7c6d-1111-4222-8333-944455556666"

    private static func current(
        division: Int = 2,
        lastChange: Int = 1
    ) -> PublicLeagueCurrent {
        PublicLeagueCurrent(
            groupID: PublicLeagueViewModelTests.groupID,
            weekStart: "2023-11-13",
            division: division,
            lastChange: lastChange
        )
    }

    private func makeSUT() -> (sut: PublicLeagueViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        let sut = PublicLeagueViewModel(
            repository: fake,
            calendar: PublicLeagueWeek.madridCalendar,
            now: { Self.now }
        )
        return (sut, fake)
    }

    private func row(
        _ place: Int,
        _ userID: String,
        _ name: String,
        xp: Int = 100,
        zone: PublicLeagueZone? = nil
    ) -> PublicLeagueRankingRow {
        PublicLeagueRankingRow(
            place: place,
            userID: userID,
            displayName: name,
            weekXP: xp,
            zone: zone
        )
    }

    // MARK: - Loading

    func testWithoutAnEntryTheQuestionHasNeverBeenAnswered() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(nil)

        await sut.load()

        XCTAssertEqual(sut.decision, .undecided)
        XCTAssertNil(sut.current)
        XCTAssertTrue(sut.ranking.isEmpty)
        XCTAssertFalse(sut.isChangeBannerVisible)
        // Nothing to ask the server for: the invitation is the whole screen.
        XCTAssertEqual(fake.currentPublicLeagueCallCount, 0)
        XCTAssertNil(sut.errorMessage)
    }

    func testAnOptedOutEntryShowsNothingPublic() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: false))

        await sut.load()

        XCTAssertEqual(sut.decision, .optedOut)
        XCTAssertNil(sut.current)
        XCTAssertTrue(sut.ranking.isEmpty)
        XCTAssertEqual(fake.currentPublicLeagueCallCount, 0)
    }

    func testAnOptedInEntryLoadsTheGroupAndTheStandings() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current())
        fake.publicLeagueRankingOutcome = .success([
            row(1, "user-a", "Ana", xp: 210, zone: .promotion),
            row(2, "user-b", "Bruno", xp: 90)
        ])

        await sut.load()

        XCTAssertEqual(sut.decision, .optedIn)
        XCTAssertEqual(sut.current, Self.current())
        XCTAssertEqual(sut.ranking.count, 2)
        XCTAssertEqual(sut.ranking.first?.xpText, "210 XP")
        XCTAssertTrue(sut.isChangeBannerVisible)
        XCTAssertEqual(sut.divisionTitle, "División 2 · Plata")
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(fake.publicLeagueRankingCallCount, 1)
    }

    func testTheDaysLeftComeFromTheInjectedClock() async {
        let (sut, _) = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.daysLeft, 5)
        XCTAssertEqual(sut.daysLeftText, "Quedan 5 días de liga")
    }

    // MARK: - Movement banner

    func testTheBannerAnnouncesAPromotion() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current(division: 2, lastChange: 1))

        await sut.load()

        XCTAssertEqual(sut.changeBannerText, "Has subido a Plata.")
    }

    func testTheBannerAnnouncesADemotion() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 1, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current(division: 1, lastChange: -1))

        await sut.load()

        XCTAssertEqual(sut.changeBannerText, "Has bajado a Bronce.")
    }

    func testTheBannerSaysTheUserStays() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 3, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current(division: 3, lastChange: 0))

        await sut.load()

        XCTAssertEqual(sut.changeBannerText, "Te mantienes en Oro.")
    }

    func testTheBannerIsDismissedByTheUser() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current())

        await sut.load()
        sut.dismissChangeBanner()

        XCTAssertFalse(sut.isChangeBannerVisible)
        // Dismissing only hides it: the group is still there.
        XCTAssertNotNil(sut.current)
    }

    // MARK: - Opt in

    func testJoinStoresTheOptInAndLoadsTheGroup() async {
        let (sut, fake) = makeSUT()
        fake.currentPublicLeagueOutcome = .success(Self.current())
        fake.publicLeagueRankingOutcome = .success([row(1, "user-a", "Ana")])

        let joined = await sut.join()

        XCTAssertTrue(joined)
        XCTAssertEqual(fake.optInCalls, [true])
        XCTAssertEqual(sut.decision, .optedIn)
        XCTAssertEqual(sut.ranking.count, 1)
        // Never played before: there is no settled week to announce.
        XCTAssertFalse(sut.isChangeBannerVisible)
        XCTAssertNil(sut.errorMessage)
    }

    func testReturningAfterAnOptOutKeepsTheMovementBanner() async {
        let (sut, fake) = makeSUT()
        // The user played once, said no, and comes back: the settled week of the
        // last participation is real information.
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 3, optedIn: false))
        fake.currentPublicLeagueOutcome = .success(Self.current(division: 4, lastChange: 1))

        await sut.load()
        let joined = await sut.join()

        XCTAssertTrue(joined)
        XCTAssertTrue(sut.isChangeBannerVisible)
        XCTAssertEqual(sut.changeBannerText, "Has subido a Platino.")
    }

    func testAFailedJoinKeepsTheInvitationAndExplainsIt() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(nil)
        fake.setOptInError = FakeLeaguesDataLoader.FakeError.network

        await sut.load()
        let joined = await sut.join()

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.decision, .undecided)
        XCTAssertEqual(sut.errorMessage, PublicLeagueViewModel.optInFailureMessage)
        XCTAssertFalse(sut.isSubmitting)
    }

    // MARK: - Opt out

    func testDeclineStoresTheOptOutAndDropsTheGroup() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current())
        fake.publicLeagueRankingOutcome = .success([row(1, "user-a", "Ana")])

        await sut.load()
        let declined = await sut.decline()

        XCTAssertTrue(declined)
        XCTAssertEqual(fake.optInCalls, [false])
        XCTAssertEqual(sut.decision, .optedOut)
        XCTAssertNil(sut.current)
        XCTAssertTrue(sut.ranking.isEmpty)
        XCTAssertFalse(sut.isChangeBannerVisible)
    }

    func testAFailedDeclineKeepsTheStateAndExplainsIt() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current())

        await sut.load()
        fake.setOptInError = FakeLeaguesDataLoader.FakeError.network
        let declined = await sut.decline()

        XCTAssertFalse(declined)
        XCTAssertEqual(sut.decision, .optedIn)
        XCTAssertNotNil(sut.current)
        XCTAssertEqual(sut.errorMessage, PublicLeagueViewModel.optOutFailureMessage)
    }

    // MARK: - Failures

    func testTheServerCanReportTheEntryAsNotOptedIn() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .failure(PublicLeagueFailure.notOptedIn)

        await sut.load()

        // The RPC raises `not_opted_in` when there is no opted-in row: the server
        // has the last word, and it is not an error the user has to read.
        XCTAssertEqual(sut.decision, .optedOut)
        XCTAssertNil(sut.errorMessage)
    }

    func testAnUnknownRpcFailureExplainsItself() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .failure(PublicLeagueFailure.unknown)

        await sut.load()

        XCTAssertEqual(sut.decision, .optedIn)
        XCTAssertNil(sut.current)
        XCTAssertEqual(sut.divisionTitle, "Liga pública")
        XCTAssertEqual(sut.errorMessage, PublicLeagueViewModel.loadFailureMessage)
    }

    func testAFailedStatusReadExplainsItself() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load()

        XCTAssertEqual(sut.errorMessage, PublicLeagueViewModel.loadFailureMessage)
        XCTAssertEqual(sut.decision, .undecided)
    }

    func testAFailedStandingsReadKeepsTheGroup() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        fake.currentPublicLeagueOutcome = .success(Self.current())
        fake.publicLeagueRankingOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load()

        XCTAssertEqual(sut.current, Self.current())
        XCTAssertTrue(sut.ranking.isEmpty)
        XCTAssertEqual(sut.errorMessage, PublicLeagueViewModel.loadFailureMessage)
    }
}
