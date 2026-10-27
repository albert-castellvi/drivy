import Foundation
import Supabase

/// Boundary between the Ligas screens and the backend (S7), so creation, join and
/// ranking are tested without a network.
protocol LeaguesDataLoading {

    func leagues(userID: String) async throws -> [LeagueRecord]

    func createLeague(name: String, inviteCode: String, userID: String) async throws -> LeagueRecord

    /// Calls `public.join_league_by_code`, which enforces the 25-member cap and
    /// returns the league id. Failures are thrown as `LeagueJoinFailure`.
    func joinLeague(inviteCode: String) async throws -> String

    /// Calls `public.league_weekly_ranking(p_league_id, p_week_start)`.
    func weeklyRanking(leagueID: String, weekStart: String) async throws -> [LeagueRankingRow]
}

/// Server-side exceptions of `public.join_league_by_code` (S7) plus the copy the
/// UI shows for them.
enum LeagueJoinFailure: Error, Equatable {

    /// The code does not match any league (`raise exception 'league_not_found'`).
    case notFound

    /// The league already has 25 members (`raise exception 'league_full'`).
    case full

    case unknown

    var message: String {
        switch self {
        case .notFound:
            return "No existe ninguna liga con ese código."
        case .full:
            return "Esa liga ya tiene 25 miembros."
        case .unknown:
            return "No hemos podido unirte a la liga. Inténtalo de nuevo."
        }
    }

    /// The RPC raises bare exception strings, so they reach the client inside the
    /// PostgREST error message (with the SQLSTATE prefix in front).
    static func from(serverMessage message: String) -> LeagueJoinFailure? {
        let normalized = message.lowercased()

        if normalized.contains("league_not_found") {
            return .notFound
        }
        if normalized.contains("league_full") {
            return .full
        }
        return nil
    }
}

enum LeagueRepositoryError: Error, Equatable {
    /// The insert worked but PostgREST returned no row to read the code from.
    case emptyInsert
}

/// S10 write/read path of the Ligas tab.
///
/// Row Level Security already limits `leagues` to the ones the user owns or
/// belongs to, so the list needs no extra membership filter; the two RPCs are
/// `security definer` functions that check the caller themselves.
struct SupabaseLeaguesRepository: LeaguesDataLoading {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func leagues(userID: String) async throws -> [LeagueRecord] {
        let rows: [LeagueRecord] = try await client
            .from("leagues")
            .select("id,name,owner_id,invite_code")
            .order("name", ascending: true)
            .execute()
            .value

        return rows
    }

    func createLeague(name: String, inviteCode: String, userID: String) async throws -> LeagueRecord {
        let rows: [LeagueRecord] = try await client
            .from("leagues")
            .insert(LeagueInsertPayload(name: name, ownerID: userID, inviteCode: inviteCode))
            .select("id,name,owner_id,invite_code")
            .execute()
            .value

        guard let league = rows.first else {
            throw LeagueRepositoryError.emptyInsert
        }

        // The creator is a member too: the weekly ranking is built on
        // `league_members`, so leaving the owner out would hide their own score.
        try await client
            .from("league_members")
            .insert(LeagueMemberInsertPayload(leagueID: league.id, userID: userID))
            .execute()

        return league
    }

    func joinLeague(inviteCode: String) async throws -> String {
        let code = LeagueInviteCode.normalize(inviteCode)

        do {
            let leagueID: String = try await client
                .rpc("join_league_by_code", params: ["p_code": code])
                .execute()
                .value

            return leagueID
        } catch {
            // The RPC raises bare exception strings, and PostgREST forwards them in
            // the error description: that is enough to map them without depending
            // on the concrete error type of the client library.
            if let failure = LeagueJoinFailure.from(serverMessage: String(describing: error)) {
                throw failure
            }
            throw LeagueJoinFailure.unknown
        }
    }

    func weeklyRanking(leagueID: String, weekStart: String) async throws -> [LeagueRankingRow] {
        let rows: [LeagueRankingRow] = try await client
            .rpc(
                "league_weekly_ranking",
                params: ["p_league_id": leagueID, "p_week_start": weekStart]
            )
            .execute()
            .value

        return rows
    }
}

/// Insert shape of `public.leagues` (S7). Keys mirror the migration verbatim.
private struct LeagueInsertPayload: Encodable {

    let name: String
    let ownerID: String
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case name
        case ownerID = "owner_id"
        case inviteCode = "invite_code"
    }
}

/// Insert shape of `public.league_members`.
private struct LeagueMemberInsertPayload: Encodable {

    let leagueID: String
    let userID: String

    enum CodingKeys: String, CodingKey {
        case leagueID = "league_id"
        case userID = "user_id"
    }
}
