import XCTest
@testable import Drivy

/// Creation and join of a league (S3), exercised with a fake Supabase boundary.
/// The 25-member cap, the eight-symbol code and the hourly attempt limit live in
/// `public.create_league` and `public.join_league_by_code`, so their answers are
/// what the UI has to translate into Spanish copy.
@MainActor
final class LeaguesViewModelTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"

    private static let league = LeagueRecord(
        id: "1c2d3e4f-1111-4222-8333-944455556666",
        name: "Los del barrio",
        ownerID: LeaguesViewModelTests.userID,
        inviteCode: "ABC23456"
    )

    private func makeSUT() -> (sut: LeaguesViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        let sut = LeaguesViewModel(repository: fake)
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

    /// S3: the client no longer generates the invite code; it sends only the name
    /// and the server draws the code in the same call that makes the league.
    func testCreateLeagueSendsOnlyTheName() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .success(Self.league)

        let created = await sut.createLeague(name: "  Los del barrio  ")

        XCTAssertTrue(created)
        XCTAssertEqual(fake.createCalls, ["Los del barrio"])
        XCTAssertEqual(sut.leagues.first, Self.league)
        XCTAssertNil(sut.createErrorMessage)
    }

    func testCreateLeagueRejectsAnEmptyName() async {
        let (sut, fake) = makeSUT()

        let created = await sut.createLeague(name: "   ")

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeaguesViewModel.emptyNameMessage)
        XCTAssertTrue(fake.createCalls.isEmpty)
    }

    func testCreateLeagueCapsTheNameAtTheSchemaLimit() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .success(Self.league)
        let longName = String(repeating: "a", count: 80)

        _ = await sut.createLeague(name: longName)

        // `leagues.name` accepts 1…60 characters (schema check).
        XCTAssertEqual(fake.createCalls.first?.count, 60)
    }

    func testCreateLeagueFailureShowsTheSpanishMessage() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        let created = await sut.createLeague(name: "Los del barrio")

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeaguesViewModel.createFailureMessage)
        XCTAssertTrue(sut.leagues.isEmpty)
    }

    // MARK: - Join

    func testJoinLeagueCallsTheRpcWithTheNormalizedCode() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .success(Self.league.id)
        fake.leaguesResult = .success([Self.league])

        let joined = await sut.joinLeague(code: "  abc 23456 ", userID: Self.userID)

        XCTAssertTrue(joined)
        XCTAssertEqual(fake.joinCalls, ["ABC23456"])
        XCTAssertNil(sut.joinErrorMessage)
        // Joining refreshes the list so the new league shows up immediately.
        XCTAssertEqual(fake.leaguesCallCount, 1)
        XCTAssertEqual(sut.leagues, [Self.league])
    }

    func testJoinLeagueAcceptsAPastedInviteLink() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .success(Self.league.id)

        _ = await sut.joinLeague(code: "https://drivy.app/l/ABC23456", userID: Self.userID)

        XCTAssertEqual(fake.joinCalls, ["ABC23456"])
    }

    func testJoinLeagueRejectsACodeOfTheWrongLength() async {
        let (sut, fake) = makeSUT()

        let joined = await sut.joinLeague(code: "ABC2345", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, LeaguesViewModel.invalidCodeMessage)
        XCTAssertEqual(
            LeaguesViewModel.invalidCodeMessage,
            "El código de invitación tiene 8 caracteres y no lleva ni O ni I."
        )
        XCTAssertTrue(fake.joinCalls.isEmpty)
    }

    /// S3: a symbol outside the server's alphabet cannot be a code, so it is
    /// refused without spending one of the ten attempts of the hour.
    func testJoinLeagueRejectsACodeWithAnImpossibleSymbol() async {
        let (sut, fake) = makeSUT()

        let joined = await sut.joinLeague(code: "ABC2345O", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, LeaguesViewModel.invalidCodeMessage)
        XCTAssertTrue(fake.joinCalls.isEmpty)
    }

    /// S3: the RPC answers null for an unknown code and for a full league alike, so
    /// the copy cannot tell the two apart either.
    func testJoinLeagueMapsTheUniformFailure() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.unavailable)

        let joined = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(
            sut.joinErrorMessage,
            "Ese código no sirve: no existe o la liga ya está completa."
        )
    }

    func testJoinLeagueMapsTooManyAttempts() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.tooManyAttempts)

        let joined = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(
            sut.joinErrorMessage,
            "Demasiados intentos. Prueba de nuevo dentro de una hora."
        )
    }

    func testJoinLeagueMapsAnUnknownFailure() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        let joined = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, "No hemos podido unirte a la liga. Inténtalo de nuevo.")
    }

    func testJoinErrorClearsOnTheNextAttempt() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.unavailable)
        _ = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        fake.joinOutcome = .success(Self.league.id)
        _ = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertNil(sut.joinErrorMessage)
    }

    // MARK: - Server message mapping

    func testJoinFailureComesFromTheServerMessage() {
        // `raise exception 'too_many_attempts'` reaches the client inside the
        // PostgREST error message, with an SQLSTATE prefix.
        XCTAssertEqual(
            LeagueJoinFailure.from(serverMessage: "P0001: too_many_attempts"),
            .tooManyAttempts
        )
        XCTAssertNil(LeagueJoinFailure.from(serverMessage: "some other failure"))
    }
}
