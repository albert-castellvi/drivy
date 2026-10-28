import XCTest
@testable import Drivy

/// S9: the share card is generated on-device, and every value it prints comes
/// from the same numbers the Hoy and Ligas screens show.
@MainActor
final class ShareCardViewModelTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"
    private static let rivalID = "22222222-3333-4444-5555-666666666666"

    /// 2026-03-10, a Tuesday, at 12:00 in Europe/Madrid.
    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }

    private var now: Date {
        madrid.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func dayKey(_ day: Int) -> String {
        let date = madrid.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))
        return DriveDay.key(for: date ?? now, calendar: madrid)
    }

    private static let league = LeagueRecord(
        id: "1c2d3e4f-1111-4222-8333-944455556666",
        name: "Los del barrio",
        ownerID: ShareCardViewModelTests.userID,
        inviteCode: "ABC234"
    )

    private func makeSUT() -> (
        sut: ShareCardViewModel,
        today: FakeTodayDataLoader,
        progress: FakeProgressDataLoader,
        leagues: FakeLeaguesDataLoader
    ) {
        let today = FakeTodayDataLoader()
        let progress = FakeProgressDataLoader()
        let leagues = FakeLeaguesDataLoader()
        let sut = ShareCardViewModel(
            todayDataLoader: today,
            progressLoader: progress,
            leaguesRepository: leagues,
            calendar: madrid,
            now: { self.now }
        )
        return (sut, today, progress, leagues)
    }

    private func drive(score: Int, distanceKm: Double = 10) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "row-1",
            startedAt: now,
            endedAt: now.addingTimeInterval(900),
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

    private func dailyScore(day: Int, score: Int) -> DailyScoreRecord {
        DailyScoreRecord(
            day: dayKey(day),
            score: score,
            distanceKm: 10,
            drivesCount: 1
        )
    }

    private func ranking(ranks: [(rank: Int, userID: String, name: String)]) -> [LeagueRankingRow] {
        ranks.map {
            LeagueRankingRow(rank: $0.rank, userID: $0.userID, displayName: $0.name, weekXP: 120)
        }
    }

    // MARK: - Values

    func testCardShowsTodaysScoreStreakAndLeaguePosition() async throws {
        let (sut, today, _, leagues) = makeSUT()
        today.dailyScoresResult = .success([dailyScore(day: 10, score: 87), dailyScore(day: 9, score: 91)])
        today.drivesResult = .success([drive(score: 87)])
        leagues.leaguesResult = .success([Self.league])
        leagues.rankingOutcome = .success(
            ranking(ranks: [(1, Self.rivalID, "Bruno"), (2, Self.userID, "Ana")])
        )

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertEqual(card.score, 87)
        XCTAssertEqual(card.streakDays, 2)
        XCTAssertEqual(card.leaguePosition, 2)
        XCTAssertEqual(card.leagueName, "Los del barrio")
        XCTAssertEqual(card.leagueSize, 2)
        XCTAssertNil(card.divisionName)
        XCTAssertEqual(card.scoreText, "87")
        XCTAssertEqual(card.streakText, "2 días de racha")
        XCTAssertEqual(card.leagueText, "2º de Los del barrio")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testCardWithoutADriveTodayShowsADash() async throws {
        let (sut, _, _, _) = makeSUT()

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.score)
        XCTAssertEqual(card.scoreText, "—")
        XCTAssertEqual(card.streakDays, 0)
        XCTAssertEqual(card.streakText, "Sin racha")
    }

    func testCardWithoutALeagueSaysSo() async throws {
        let (sut, today, _, leagues) = makeSUT()
        today.drivesResult = .success([drive(score: 74)])
        leagues.leaguesResult = .success([])

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.leaguePosition)
        XCTAssertEqual(card.leagueText, "Sin liga esta semana")
        XCTAssertTrue(card.showsLeagueLine)
    }

    func testRankingIsAskedForTheCurrentMonday() async {
        let (sut, _, _, leagues) = makeSUT()
        leagues.leaguesResult = .success([Self.league])

        await sut.load(userID: Self.userID)

        XCTAssertEqual(leagues.rankingCalls.first?.leagueID, Self.league.id)
        XCTAssertEqual(leagues.rankingCalls.first?.weekStart, "2026-03-09")
    }

    /// A broken ranking only drops the position: the card is still shareable.
    func testRankingFailureStillProducesACard() async throws {
        let (sut, today, _, leagues) = makeSUT()
        today.drivesResult = .success([drive(score: 74)])
        leagues.leaguesResult = .success([Self.league])
        leagues.rankingOutcome = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.leaguePosition)
        XCTAssertEqual(card.score, 74)
    }

    func testTodayReadFailureShowsTheSpanishMessage() async {
        let (sut, today, _, _) = makeSUT()
        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertNil(sut.card)
        XCTAssertEqual(sut.errorMessage, ShareCardViewModel.loadFailureMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Streak v2 (S1)

    /// S1/S8: the card counts the freezes of the plan in force, so free and premium
    /// do not see the same run.
    func testTheStreakUsesThePlanFreezes() async throws {
        let (sut, today, _, _) = makeSUT()
        // 1 March is clean; 2, 3 and 4 are failures of the same week; 8, 9 and 10
        // are clean again.
        today.dailyScoresResult = .success([
            dailyScore(day: 1, score: 90),
            dailyScore(day: 2, score: 60),
            dailyScore(day: 3, score: 60),
            dailyScore(day: 4, score: 60),
            dailyScore(day: 8, score: 90),
            dailyScore(day: 9, score: 90),
            dailyScore(day: 10, score: 90)
        ])

        await sut.load(userID: Self.userID, plan: .premium)
        let premium = try XCTUnwrap(sut.card)

        await sut.load(userID: Self.userID, plan: .free)
        let free = try XCTUnwrap(sut.card)

        XCTAssertEqual(premium.streakDays, 4)
        XCTAssertEqual(free.streakDays, 3)
    }

    // MARK: - Public division (S9)

    func testTheDivisionIsShownWhenTheUserOptedIn() async throws {
        let (sut, _, _, leagues) = makeSUT()
        leagues.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertEqual(card.divisionName, "Plata")
        XCTAssertEqual(card.divisionText, "Liga Plata")
    }

    func testTheDivisionIsHiddenWhenTheUserOptedOut() async throws {
        let (sut, _, _, leagues) = makeSUT()
        leagues.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 4, optedIn: false))

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.divisionName)
        XCTAssertNil(card.divisionText)
    }

    func testTheDivisionIsHiddenWithoutADecision() async throws {
        let (sut, _, _, leagues) = makeSUT()
        leagues.publicLeagueStatusResult = .success(nil)

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.divisionName)
    }

    /// A failing read only drops the division: the card is still worth sharing.
    func testDivisionFailureOnlyDropsTheDivision() async throws {
        let (sut, today, _, leagues) = makeSUT()
        today.drivesResult = .success([drive(score: 88)])
        leagues.publicLeagueStatusResult = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        let card = try XCTUnwrap(sut.card)
        XCTAssertNil(card.divisionName)
        XCTAssertEqual(card.score, 88)
    }

    /// S9: the entry is read with a plain select. `public_league_current()` settles
    /// the previous week and places the user in a group, which a share card must
    /// never trigger.
    func testTheCardNeverCallsTheLeagueRpcWithSideEffects() async {
        let (sut, _, _, leagues) = makeSUT()
        leagues.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 1, optedIn: true))

        await sut.load(userID: Self.userID)

        XCTAssertGreaterThan(leagues.publicLeagueStatusCallCount, 0)
        XCTAssertEqual(leagues.currentPublicLeagueCallCount, 0)
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

    func testAccessibilitySummaryNamesTheDivision() {
        let card = ShareCardModel(
            score: 87,
            streakDays: 3,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0,
            divisionName: "Oro"
        )

        XCTAssertEqual(card.accessibilitySummary, "Driver Score 87. 3 días de racha. Liga Oro.")
        XCTAssertFalse(card.showsLeagueLine)
    }
}
