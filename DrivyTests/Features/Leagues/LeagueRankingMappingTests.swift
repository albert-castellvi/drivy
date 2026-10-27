import XCTest
@testable import Drivy

/// The weekly rankings must map the RPC/table columns of the schema (S5, S10).
/// Both rankings sort by weekly XP: the old `avg_score`/`total_km` columns are
/// gone from `league_weekly_ranking`.
final class LeagueRankingMappingTests: XCTestCase {

    func testRankingRowMapsTheRpcColumns() throws {
        let row = try PostgrestFixtures.decode(
            LeagueRankingRow.self,
            from: PostgrestFixtures.rankingRowJSON
        )

        XCTAssertEqual(row.rank, 1)
        XCTAssertEqual(row.userID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(row.displayName, "Ana")
        XCTAssertEqual(row.weekXP, 180)
        XCTAssertEqual(row.xpText, "180 XP")
        XCTAssertEqual(row.id, row.userID)
    }

    func testRankingRowAcceptsPlainNumbers() throws {
        let json = """
        {
          "rank": 2,
          "user_id": "22222222-3333-4444-5555-666666666666",
          "display_name": "Bruno",
          "week_xp": 0
        }
        """

        let row = try PostgrestFixtures.decode(LeagueRankingRow.self, from: json)

        XCTAssertEqual(row.rank, 2)
        XCTAssertEqual(row.weekXP, 0)
        XCTAssertEqual(row.xpText, "0 XP")
    }

    func testLeagueRowMapsTheSchemaColumns() throws {
        let row = try PostgrestFixtures.decode(
            LeagueRecord.self,
            from: PostgrestFixtures.leagueRowJSON
        )

        XCTAssertEqual(row.id, "1c2d3e4f-1111-4222-8333-944455556666")
        XCTAssertEqual(row.name, "Los del barrio")
        XCTAssertEqual(row.ownerID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(row.inviteCode, "ABC234")
    }
}
