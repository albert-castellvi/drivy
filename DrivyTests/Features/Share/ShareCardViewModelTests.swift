import XCTest
@testable import Drivy

/// S8: the share card is generated on-device, and every value it prints comes
/// from the same numbers the Hoy and Ligas screens show.
@MainActor
final class ShareCardViewModelTests: XCTestCase {

    /// 2023-11-14T22:13:20Z, i.e. 2023-11-14 in UTC.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userID = "11111111-2222-3333-4444-555555555555"

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static let league = LeagueRecord(
        id: "1c2d3e4f-1111-4222-8333-944455556666",
        name: "Los del barrio",
        ownerID: ShareCardViewModelTests.userID,
        inviteCode: "ABC234"
    )

    private func makeSUT() -> (sut: ShareCardViewModel, today: FakeTodayDataLoader, leagues: FakeLeaguesDataLoader) {
        let today = FakeTodayDataLoader()
        let leagues = FakeLeaguesDataLoader()
        let sut = ShareCardViewModel(
            todayDataLoader: today,
            leaguesRepository: leagues,
            calendar: utc,
            now: { Self.now }
        )
        return (sut, today, leagues)
    }

    private func drive(score: Int, distanceKm: Double = 10) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "row-1",
            startedAt: Self.now,
            endedAt: Self.now.addingTimeInterval(900),
            distanceKm: distanceKm,
            durationSeconds: 900,
            score: score,
            harshBrakes: 0,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: true
        )
    }

    private func ranking(ranks: [(rank: Int, userID: String, name: String)]) -> [LeagueRankingRow] {
        ranks.map {
            LeagueRankingRow(
                rank: $0.rank,
                userID: $0.userID,
                displayName: $0.name,
                averageScore: 90,
                totalKm: 20
            )
        }
    }

    // MARK: - Values

    func testCardShowsTodaysScoreStreakAndLeaguePosition() async throws {
        let (sut, today, leagues) = makeSUT()
        today.dailyScoresResult = .success([
            DailyScoreRecord(day: "2023-11-14", score: 87, distanceKm: 12.34, drivesCount: 1),
            DailyScoreRecord(day: "2023-11-13", score: 91, distanceKm: 9, drivesCount: 1)
        ])
        today.drivesResult = .success([drive(score: 87)])
        leagues.leaguesResult = .success([Self.league])
        leagues.rankingOutcome = .success(
            ranking(ranks: [
                (1, "22222222-3333-4444-5555-666666666666", "Bruno"),
                (2, Self.userID, "Ana")
            ])
        )

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertEqual(card.score, 87)
        XCTAssertEqual(card.streakDays, 2)
        XCTAssertEqual(card.leaguePosition, 2)
        XCTAssertEqual(card.leagueName, "Los del barrio")
        XCTAssertEqual(card.leagueSize, 2)
        XCTAssertEqual(card.scoreText, "87")
        XCTAssertEqual(card.streakText, "2 días de racha")
        XCTAssertEqual(card.leagueText, "2º de Los del barrio")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testCardWithoutADriveTodayShowsADash() async throws {
        let (sut, _, _) = makeSUT()

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.score)
        XCTAssertEqual(card.scoreText, "—")
        XCTAssertEqual(card.streakDays, 0)
        XCTAssertEqual(card.streakText, "Sin racha")
    }

    func testCardWithoutALeagueSaysSo() async throws {
        let (sut, today, leagues) = makeSUT()
        today.drivesResult = .success([drive(score: 74)])
        leagues.leaguesResult = .success([])

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.leaguePosition)
        XCTAssertEqual(card.leagueText, "Sin liga esta semana")
    }

    func testRankingIsAskedForTheCurrentMonday() async {
        let (sut, _, leagues) = makeSUT()
        leagues.leaguesResult = .success([Self.league])

        await sut.load(userID: Self.userID)

        XCTAssertEqual(leagues.rankingCalls.first?.leagueID, Self.league.id)
        XCTAssertEqual(leagues.rankingCalls.first?.weekStart, "2023-11-13")
    }

    /// A broken ranking only drops the position: the card is still shareable.
    func testRankingFailureStillProducesACard() async throws {
        let (sut, today, leagues) = makeSUT()
        today.drivesResult = .success([drive(score: 74)])
        leagues.leaguesResult = .success([Self.league])
        leagues.rankingOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.leaguePosition)
        XCTAssertEqual(card.score, 74)
    }

    func testTodayReadFailureShowsTheSpanishMessage() async {
        let (sut, today, _) = makeSUT()
        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertNil(sut.card)
        XCTAssertEqual(sut.errorMessage, ShareCardViewModel.loadFailureMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Copy

    func testStreakCopyUsesSingularForOneDay() {
        let card = ShareCardModel(
            score: 90,
            streakDays: 1,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0
        )

        XCTAssertEqual(card.streakText, "1 día de racha")
    }

    func testLeagueCopyWithoutANameStillShowsThePosition() {
        let card = ShareCardModel(
            score: 90,
            streakDays: 3,
            leaguePosition: 5,
            leagueName: nil,
            leagueSize: 8
        )

        XCTAssertEqual(card.leagueText, "5º de la liga")
    }

    func testAccessibilitySummaryCombinesEveryValue() {
        let card = ShareCardModel(
            score: 87,
            streakDays: 3,
            leaguePosition: 2,
            leagueName: "Los del barrio",
            leagueSize: 4
        )

        XCTAssertEqual(
            card.accessibilitySummary,
            "Driver Score 87. 3 días de racha. 2º de Los del barrio."
        )
    }
}
