import XCTest
@testable import Drivy

/// The weekly rankings must map the RPC/table columns of the schema (S5, S10).
/// Both rankings sort by weekly XP and mark the caller's row with `is_me` instead
/// of returning uuids (S2).
final class LeagueRankingMappingTests: XCTestCase {

    func testRankingRowMapsTheRpcColumns() throws {
        let row = try PostgrestFixtures.decode(
            LeagueRankingRow.self,
            from: PostgrestFixtures.rankingRowJSON
        )

        XCTAssertEqual(row.rank, 1)
        XCTAssertEqual(row.displayName, "Ana")
        XCTAssertEqual(row.weekXP, 180)
        XCTAssertEqual(row.xpText, "180 XP")
        XCTAssertTrue(row.isMe)
        XCTAssertEqual(row.id, "1-Ana")
    }

    func testRankingRowAcceptsPlainNumbers() throws {
        let json = """
        {
          "rank": 2,
          "display_name": "Bruno",
          "week_xp": 0,
          "is_me": false
        }
        """

        let row = try PostgrestFixtures.decode(LeagueRankingRow.self, from: json)

        XCTAssertEqual(row.rank, 2)
        XCTAssertEqual(row.weekXP, 0)
        XCTAssertEqual(row.xpText, "0 XP")
        XCTAssertFalse(row.isMe)
        XCTAssertEqual(row.id, "2-Bruno")
    }

    /// S2: two members with the same visible name still get distinct identities,
    /// because the rank is part of it.
    func testRowsOfTheSameNameHaveDifferentIdentities() throws {
        let first = try PostgrestFixtures.decode(
            LeagueRankingRow.self,
            from: PostgrestFixtures.rankingRowJSON
        )
        let second = LeagueRankingRow(rank: 2, displayName: "Ana", weekXP: 90, isMe: false)

        XCTAssertNotEqual(first.id, second.id)
    }

    func testLeagueRowMapsTheSchemaColumns() throws {
        let row = try PostgrestFixtures.decode(
            LeagueRecord.self,
            from: PostgrestFixtures.leagueRowJSON
        )

        XCTAssertEqual(row.id, "1c2d3e4f-1111-4222-8333-944455556666")
        XCTAssertEqual(row.name, "Los del barrio")
        XCTAssertEqual(row.ownerID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(row.inviteCode, "ABC23456")
    }
}
