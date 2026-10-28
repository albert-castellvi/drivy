import XCTest
@testable import Drivy

/// The league detail ranking (S5): the current ISO week, straight from
/// `public.league_weekly_ranking`, ordered by weekly XP.
@MainActor
final class LeagueRankingViewModelTests: XCTestCase {

    /// 2023-11-14T22:13:20Z, i.e. Tuesday 2023-11-14 in UTC.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let leagueID = "1c2d3e4f-1111-4222-8333-944455556666"

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func makeSUT() -> (sut: LeagueRankingViewModel, fake: FakeLeaguesDataLoader) {
        let fake = FakeLeaguesDataLoader()
        let sut = LeagueRankingViewModel(
            leagueID: Self.leagueID,
            repository: fake,
            calendar: utc,
            now: { Self.now }
        )
        return (sut, fake)
    }

    private func row(_ rank: Int, _ name: String, xp: Int = 150, isMe: Bool = false) -> LeagueRankingRow {
        LeagueRankingRow(rank: rank, displayName: name, weekXP: xp, isMe: isMe)
    }

    func testLoadPublishesTheWeeklyRows() async {
        let (sut, fake) = makeSUT()
        fake.rankingOutcome = .success([
            row(1, "Ana", xp: 210, isMe: true),
            row(2, "Bruno", xp: 90)
        ])

        await sut.load()

        XCTAssertEqual(sut.rows.count, 2)
        XCTAssertEqual(sut.rows.first?.displayName, "Ana")
        XCTAssertEqual(sut.rows.first?.weekXP, 210)
        XCTAssertEqual(sut.rows.first?.xpText, "210 XP")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    /// S2: the caller's row is identified by the server's `is_me` mark, which is the
    /// only thing the view model can use now that the payload carries no uuids.
    func testTheOwnRowIsTheOneTheServerMarked() async {
        let (sut, fake) = makeSUT()
        fake.rankingOutcome = .success([
            row(1, "Bruno", xp: 210),
            row(2, "Ana", xp: 90, isMe: true)
        ])

        await sut.load()

        XCTAssertEqual(sut.rows.filter(\.isMe).map(\.displayName), ["Ana"])
    }

    func testRankingIsRequestedForTheCurrentMonday() async {
        let (sut, fake) = makeSUT()

        await sut.load()

        XCTAssertEqual(fake.rankingCalls.first?.leagueID, Self.leagueID)
        XCTAssertEqual(fake.rankingCalls.first?.weekStart, "2023-11-13")
        XCTAssertEqual(sut.weekStartLabel, "13 nov")
    }

    func testLoadFailureShowsTheSpanishMessage() async {
        let (sut, fake) = makeSUT()
        fake.rankingOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load()

        XCTAssertEqual(sut.errorMessage, LeagueRankingViewModel.loadFailureMessage)
        XCTAssertTrue(sut.rows.isEmpty)
    }
}
