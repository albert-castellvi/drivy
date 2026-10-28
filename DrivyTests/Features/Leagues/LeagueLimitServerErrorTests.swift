import XCTest
@testable import Drivy

/// Server-side enforcement of the free one-league cap (S5.1) as seen by the
/// client (S5.3): when `create_league` or `join_league_by_code` raise
/// `league_limit`, the screens show exactly the copy the client gate
/// (`LeagueLimitGate`) already uses — no new strings.
///
/// The server answers are exercised with the shared fake `LeaguesDataLoading`
/// boundary: the mapped failures are thrown exactly like the real repository
/// throws them, and the raw PostgREST message mapping (`P0001` prefix plus the
/// bare exception string) is asserted on `LeagueJoinFailure.from`.
@MainActor
final class LeagueLimitServerErrorTests: XCTestCase {

    /// Error that describes itself like PostgREST does: the SQLSTATE prefix
    /// in front of the raised message.
    private struct PostgrestLikeError: Error, Equatable {
        let message: String
    }

    private static let userID = "11111111-2222-3333-4444-555555555555"

    private func makeSUT() -> (sut: LeaguesViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        let sut = LeaguesViewModel(repository: fake)
        return (sut, fake)
    }

    // MARK: - Server message mapping

    func testLeagueLimitIsMappedFromTheServerMessage() {
        XCTAssertEqual(
            LeagueJoinFailure.from(serverMessage: "P0001: league_limit"),
            .leagueLimit
        )
        // Case-insensitive, like the existing mappings.
        XCTAssertEqual(
            LeagueJoinFailure.from(serverMessage: "P0001: LEAGUE_LIMIT"),
            .leagueLimit
        )
    }

    func testOtherMessagesStillMapAsBefore() {
        XCTAssertEqual(
            LeagueJoinFailure.from(serverMessage: "P0001: too_many_attempts"),
            .tooManyAttempts
        )
        XCTAssertNil(LeagueJoinFailure.from(serverMessage: "P0001: something_else"))
        XCTAssertNil(LeagueJoinFailure.from(serverMessage: "daily_drive_limit"))
    }

    func testLeagueLimitCarriesTheClientGateCopy() {
        XCTAssertEqual(LeagueJoinFailure.leagueLimit.message, LeagueLimitGate.limitMessage)
    }

    // MARK: - Creation

    /// The real repository throws the mapped `LeagueJoinFailure.leagueLimit`
    /// (the message mapping is asserted below); the view model shows the
    /// client-gate copy, not the generic failure sentence.
    func testCreateLeagueShowsTheLimitCopyWhenTheServerRaisesLeagueLimit() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .failure(LeagueJoinFailure.leagueLimit)

        let created = await sut.createLeague(name: "Mi liga")

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeagueLimitGate.limitMessage)
        XCTAssertNotEqual(sut.createErrorMessage, LeaguesViewModel.createFailureMessage)
    }

    func testCreateLeagueKeepsTheGenericCopyForOtherServerErrors() async {
        let (sut, fake) = makeSUT()
        fake.createOutcome = .failure(PostgrestLikeError(message: "P0001: something_else"))

        let created = await sut.createLeague(name: "Mi liga")

        XCTAssertFalse(created)
        XCTAssertEqual(sut.createErrorMessage, LeaguesViewModel.createFailureMessage)
    }

    // MARK: - Join

    func testJoinLeagueShowsTheLimitCopyWhenTheServerRaisesLeagueLimit() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(LeagueJoinFailure.leagueLimit)

        let joined = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, LeagueLimitGate.limitMessage)
        XCTAssertNotEqual(sut.joinErrorMessage, LeagueJoinFailure.unknown.message)
    }

    func testJoinLeagueKeepsTheGenericCopyForOtherServerErrors() async {
        let (sut, fake) = makeSUT()
        fake.joinOutcome = .failure(PostgrestLikeError(message: "P0001: something_else"))

        let joined = await sut.joinLeague(code: "ABC23456", userID: Self.userID)

        XCTAssertFalse(joined)
        XCTAssertEqual(sut.joinErrorMessage, LeagueJoinFailure.unknown.message)
    }
}
