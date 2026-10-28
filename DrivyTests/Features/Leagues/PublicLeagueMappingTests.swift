import XCTest
@testable import Drivy

/// The public league payloads must map the columns of `public_league_entries`,
/// `public_league_current()` and `public_league_ranking()` (S5).
final class PublicLeagueMappingTests: XCTestCase {

    func testTheOwnEntryMapsTheTableColumns() throws {
        let status = try PostgrestFixtures.decode(
            PublicLeagueStatus.self,
            from: PostgrestFixtures.publicLeagueStatusJSON
        )

        XCTAssertEqual(status.division, 2)
        XCTAssertTrue(status.optedIn)
    }

    func testAnOptedOutEntryIsRead() throws {
        let json = """
        {"division": 4, "opted_in": false}
        """

        let status = try PostgrestFixtures.decode(PublicLeagueStatus.self, from: json)

        XCTAssertEqual(status.division, 4)
        XCTAssertFalse(status.optedIn)
    }

    func testTheCurrentGroupMapsTheRpcColumns() throws {
        let current = try PostgrestFixtures.decode(
            PublicLeagueCurrent.self,
            from: PostgrestFixtures.publicLeagueCurrentJSON
        )

        XCTAssertEqual(current.groupID, "9a8b7c6d-1111-4222-8333-944455556666")
        // `week_start` is a `date`: PostgREST sends the same `yyyy-MM-dd` text the
        // RPCs accept as `p_week_start`.
        XCTAssertEqual(current.weekStart, "2023-11-13")
        XCTAssertEqual(current.division, 2)
        XCTAssertEqual(current.lastChange, 1)
    }

    func testADemotionOfTheLastSettledWeekIsRead() throws {
        let json = """
        {
          "group_id": "9a8b7c6d-1111-4222-8333-944455556666",
          "week_start": "2023-11-13",
          "division": "1",
          "last_change": "-1"
        }
        """

        let current = try PostgrestFixtures.decode(PublicLeagueCurrent.self, from: json)

        XCTAssertEqual(current.division, 1)
        XCTAssertEqual(current.lastChange, -1)
    }

    func testTheStandingRowMapsThePlaceTheXpAndTheZone() throws {
        let row = try PostgrestFixtures.decode(
            PublicLeagueRankingRow.self,
            from: PostgrestFixtures.publicLeagueRankingRowJSON
        )

        XCTAssertEqual(row.place, 3)
        XCTAssertEqual(row.displayName, "Ana")
        XCTAssertEqual(row.weekXP, 120)
        XCTAssertEqual(row.xpText, "120 XP")
        XCTAssertEqual(row.zone, .promotion)
        XCTAssertTrue(row.isMe)
        XCTAssertEqual(row.id, "3-Ana")
    }

    /// S2: the payload carries no uuid at all, only the server's mark of the
    /// caller's row, so another member's row decodes as `isMe == false`.
    func testSomebodyElsesRowIsNotMarkedAsMine() throws {
        let row = try PostgrestFixtures.decode(
            PublicLeagueRankingRow.self,
            from: PostgrestFixtures.publicLeagueRankingRowWithoutZoneJSON
        )

        XCTAssertFalse(row.isMe)
    }

    func testANullZoneMeansNoMovement() throws {
        let row = try PostgrestFixtures.decode(
            PublicLeagueRankingRow.self,
            from: PostgrestFixtures.publicLeagueRankingRowWithoutZoneJSON
        )

        XCTAssertEqual(row.place, 9)
        XCTAssertEqual(row.weekXP, 40)
        XCTAssertNil(row.zone)
    }

    func testTheDemotionZoneIsRead() throws {
        let json = """
        {
          "place": 28,
          "display_name": "Carla",
          "week_xp": 0,
          "zone": "demotion",
          "is_me": false
        }
        """

        let row = try PostgrestFixtures.decode(PublicLeagueRankingRow.self, from: json)

        XCTAssertEqual(row.zone, .demotion)
        XCTAssertEqual(row.zone?.label, "Descenso")
    }

    func testAnUnknownZoneIsReadAsNoMovement() throws {
        // A future band must not blank the standings of an older build.
        let json = """
        {
          "place": 4,
          "display_name": "Diego",
          "week_xp": 60,
          "zone": "promotion_playoff",
          "is_me": false
        }
        """

        let row = try PostgrestFixtures.decode(PublicLeagueRankingRow.self, from: json)

        XCTAssertNil(row.zone)
        XCTAssertEqual(row.weekXP, 60)
    }

    // MARK: - Server exceptions

    func testTheNotOptedInExceptionOfTheRpcIsMapped() {
        // The function raises a bare string, so it reaches the client inside the
        // PostgREST error description, like `LeagueJoinFailure` does.
        let message = "PostgrestError(message: \"not_opted_in\", code: \"P0001\")"

        XCTAssertEqual(PublicLeagueFailure.from(serverMessage: message), .notOptedIn)
    }

    func testAnUnrelatedServerErrorIsNotOneOfTheKnownExceptions() {
        XCTAssertNil(PublicLeagueFailure.from(serverMessage: "JWT expired"))
    }
}
