import Foundation
@testable import Drivy

/// Fixtures of the payloads PostgREST returns for the core screens (T4).
///
/// They are kept as raw JSON on purpose: decoding them is what proves the row
/// types match the column names of the schema (S10), and the numeric/date
/// leniency is exercised with the two shapes Postgres can serialize.
enum PostgrestFixtures {

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// `public.drives` row: `numeric` as a JSON number, `timestamptz` with
    /// fractional seconds.
    static let driveRowJSON = """
    {
      "id": "0b0d1f4e-1111-4222-8333-944455556666",
      "started_at": "2023-11-14T22:13:20.123456+00:00",
      "ended_at": "2023-11-14T22:31:50.654321+00:00",
      "distance_km": 12.34,
      "duration_s": 1110,
      "score": 87,
      "harsh_brakes": 2,
      "harsh_accelerations": 1,
      "phone_use_events": 0,
      "speeding_events": 3,
      "connected_mode": true
    }
    """

    /// `public.daily_scores` row with the decimal sent as a string, which is the
    /// other shape PostgREST can use for a `numeric`.
    static let dailyScoreRowJSON = """
    {"day": "2023-11-14", "score": 87, "distance_km": "12.34", "drives_count": 1}
    """

    static let leagueRowJSON = """
    {
      "id": "1c2d3e4f-1111-4222-8333-944455556666",
      "name": "Los del barrio",
      "owner_id": "11111111-2222-3333-4444-555555555555",
      "invite_code": "ABC234"
    }
    """

    /// `public.league_weekly_ranking(...)` row: `rank` is a bigint and
    /// `avg_score`/`total_km` are numerics, so everything can arrive as a string.
    static let rankingRowJSON = """
    {
      "rank": "1",
      "user_id": "11111111-2222-3333-4444-555555555555",
      "display_name": "Ana",
      "avg_score": "91.6",
      "total_km": "34.20"
    }
    """
}
