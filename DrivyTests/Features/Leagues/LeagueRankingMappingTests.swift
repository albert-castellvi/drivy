import XCTest
@testable import Drivy

/// The weekly ranking and the league rows must map the RPC/table columns of the
/// schema (S7, S10).
final class LeagueRankingMappingTests: XCTestCase {

    func testRankingRowMapsTheRpcColumns() throws {
        let row = try PostgrestFixtures.decode(
            LeagueRankingRow.self,
            from: PostgrestFixtures.rankingRowJSON
        )

        XCTAssertEqual(row.rank, 1)
        XCTAssertEqual(row.userID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(row.displayName, "Ana")
        // 91.6 is rounded to the nearest point, like every score in the app.
        XCTAssertEqual(row.averageScore, 92)
        XCTAssertEqual(row.totalKm, 34.2)
        XCTAssertEqual(row.id, row.userID)
    }

    func testRankingRowAcceptsPlainNumbers() throws {
        let json = """
        {
          "rank": 2,
          "user_id": "22222222-3333-4444-5555-666666666666",
          "display_name": "Bruno",
          "avg_score": 88,
          "total_km": 12.5
        }
        """

        let row = try PostgrestFixtures.decode(LeagueRankingRow.self, from: json)

        XCTAssertEqual(row.rank, 2)
        XCTAssertEqual(row.averageScore, 88)
        XCTAssertEqual(row.totalKm, 12.5)
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
