import XCTest
@testable import Drivy

/// Creation and join of a league (S7), exercised with a fake Supabase boundary.
/// The 25-member cap lives in `public.join_league_by_code`, so its exceptions are
/// what the UI has to translate into Spanish copy.
@MainActor
final class LeaguesViewModelTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"

    private static let league = LeagueRecord(
        id: "1c2d3e4f-1111-4222-8333-944455556666",
        name: "Los del barrio",
        ownerID: LeaguesViewModelTests.userID,
        inviteCode: "ABC234"
    )

    private func makeSUT(inviteCode: String = "ABC234") -> (sut: LeaguesViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        let sut = LeaguesViewModel(repository: fake, inviteCodeGenerator: { inviteCode })
        return (sut, fake)
    }

    // MARK: - Loading

    func testLoadPublishesTheUsersLeagues() async {
        let (sut, fake) = makeSUT()
        fake.leaguesResult = .success([Self.league])

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.leagues, [Self.league])
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadFailureShowsTheSpanishMessage() async {
        let (sut, fake) = makeSUT()
        fake.leaguesResult = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.errorMessage, LeaguesViewModel.loadFailureMessage)
        XCTAssertTrue(sut.leagues.isEmpty)
    }

    // MARK: - Creation

    func testCreateLeagueUsesTheGeneratedInviteCode() async {
        let (sut, fake) = makeSUT(inviteCode: "XYZ789")
        fake.createOutcome = .success(Self.league)

        let created = await sut.createLeague(name: "  Los del barrio  ", userID: Self.userID)

        XCTAssertTrue(created)
        let call = fake.createCalls.first
        XCTAssertEqual(call?.name, "Los del barrio")
        XCTAssertEqual(call?.inviteCode, "XYZ789")
        XCTAssertEqual(call?.userID, Self.userID)
        XCTAssertEqual(sut.leagues.first, Self.league)
        XCTAssertNil(sut.createErrorMessage)
    }

    func testCreateLeagueRejectsAnEmptyName() async {
        let (sut, fake) = makeSUT()

        let created = await sut.createLeague(name: "   ", userID: Self.userID)

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeaguesViewModel.emptyNameMessage)
        XCTAssertTrue(fake.createCalls.isEmpty)
    }

    func testCreateLeagueCapsTheNameAtTheSchemaLimit() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .success(Self.league)
        let longName = String(repeating: "a", count: 80)

        _ = await sut.createLeague(name: longName, userID: Self.userID)

        // `leagues.name` accepts 1…60 characters (schema check).
        XCTAssertEqual(fake.createCalls.first?.name.count, 60)
    }

    func testCreateLeagueFailureShowsTheSpanishMessage() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        let created = await sut.createLeague(name: "Los del barrio", userID: Self.userID)

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeaguesViewModel.createFailureMessage)
        XCTAssertTrue(sut.leagues.isEmpty)
    }

    // MARK: - Join

    func testJoinLeagueCallsTheRpcWithTheNormalizedCode() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .success(Self.league.id)
        fake.leaguesResult = .success([Self.league])

        let joined = await sut.joinLeague(code: "  abc234 ", userID: Self.userID)

        XCTAssertTrue(joined)
        XCTAssertEqual(fake.joinCalls, ["ABC234"])
        XCTAssertNil(sut.joinErrorMessage)
        // Joining refreshes the list so the new league shows up immediately.
        XCTAssertEqual(fake.leaguesCallCount, 1)
        XCTAssertEqual(sut.leagues, [Self.league])
    }

    func testJoinLeagueAcceptsAPastedInviteLink() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .success(Self.league.id)

        _ = await sut.joinLeague(code: "https://drivy.app/l/ABC234", userID: Self.userID)

        XCTAssertEqual(fake.joinCalls, ["ABC234"])
    }

    func testJoinLeagueRejectsACodeOfTheWrongLength() async {
        let (sut, fake) = makeSUT()

        let joined = await sut.joinLeague(code: "ABC", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, LeaguesViewModel.invalidCodeMessage)
        XCTAssertTrue(fake.joinCalls.isEmpty)
    }

    func testJoinLeagueMapsLeagueNotFound() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.notFound)

        let joined = await sut.joinLeague(code: "ABC234", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, "No existe ninguna liga con ese código.")
    }

    func testJoinLeagueMapsLeagueFull() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.full)

        let joined = await sut.joinLeague(code: "ABC234", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, "Esa liga ya tiene 25 miembros.")
    }

    func testJoinLeagueMapsAnUnknownFailure() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        let joined = await sut.joinLeague(code: "ABC234", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, "No hemos podido unirte a la liga. Inténtalo de nuevo.")
    }

    func testJoinErrorClearsOnTheNextAttempt() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.full)
        _ = await sut.joinLeague(code: "ABC234", userID: Self.userID)

        fake.joinOutcome = .success(Self.league.id)
        _ = await sut.joinLeague(code: "ABC234", userID: Self.userID)

        XCTAssertNil(sut.joinErrorMessage)
    }

    // MARK: - Server message mapping

    func testJoinFailureComesFromTheServerMessage() {
        // `raise exception 'league_not_found'` reaches the client inside the
        // PostgREST error message, with an SQLSTATE prefix.
        XCTAssertEqual(
            LeagueJoinFailure.from(serverMessage: "P0001: league_not_found"),
            .notFound
        )
        XCTAssertEqual(LeagueJoinFailure.from(serverMessage: "league_full"), .full)
        XCTAssertNil(LeagueJoinFailure.from(serverMessage: "some other failure"))
    }
}
