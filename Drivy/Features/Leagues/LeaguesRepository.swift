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

    /// Calls `public.league_weekly_ranking(p_league_id, p_week_start)`, which
    /// ranks the members of the league by weekly XP (S5).
    func weeklyRanking(leagueID: String, weekStart: String) async throws -> [LeagueRankingRow]

    // MARK: - Public leagues (S5)

    /// Calls `public.set_public_league_opt_in(p_on)`. `false` also leaves the
    /// current week's group, so the name disappears from it.
    func setPublicLeagueOptIn(_ on: Bool) async throws

    /// Own row of `public.public_league_entries`: the decision and the division.
    /// `nil` means the user never decided.
    func publicLeagueStatus() async throws -> PublicLeagueStatus?

    /// Calls `public.public_league_current()`, which lazily settles the previous
    /// week and places the caller in a group. Throws
    /// `PublicLeagueFailure.notOptedIn` when the server says there is no
    /// opted-in entry.
    func currentPublicLeague() async throws -> PublicLeagueCurrent

    /// Calls `public.public_league_ranking()`: the standings of the caller's
    /// group this week, best place first.
    func publicLeagueRanking() async throws -> [PublicLeagueRankingRow]
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

/// Server-side exception of `public.public_league_current()` (S5), mapped like
/// `LeagueJoinFailure`: the RPC raises a bare exception string, so the mapping
/// reads the PostgREST error description.
///
/// It carries no copy on purpose: being not opted in is a state the screen
/// renders (the invitation or nothing), not a sentence the user has to read,
/// and the view model owns the messages of the failures that are errors.
enum PublicLeagueFailure: Error, Equatable {

    /// The caller has no opted-in entry (`raise exception 'not_opted_in'`).
    case notOptedIn

    case unknown

    /// `nil` when the message is not one of the exceptions this feature knows:
    /// the caller decides what an unexpected failure means.
    static func from(serverMessage message: String) -> PublicLeagueFailure? {
        let normalized = message.lowercased()

        if normalized.contains("not_opted_in") {
            return .notOptedIn
        }
        return nil
    }
}

enum LeagueRepositoryError: Error, Equatable {
    /// The insert worked but PostgREST returned no row to read the code from.
    case emptyInsert
}

/// Write/read path of the Ligas tab (S5, S10).
///
/// Row Level Security already limits `leagues` to the ones the user owns or
/// belongs to, so the list needs no extra membership filter; the RPCs are
/// `security definer` functions that check the caller themselves. The public
/// league tables have no client-writable policy at all: every public read and
/// write goes through the RPCs below.
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

    // MARK: - Public leagues (S5)

    func setPublicLeagueOptIn(_ on: Bool) async throws {
        try await client
            .rpc("set_public_league_opt_in", params: ["p_on": on])
            .execute()
    }

    func publicLeagueStatus() async throws -> PublicLeagueStatus? {
        // The select policy of the table only exposes the own row, so an empty
        // answer means the user never decided.
        let rows: [PublicLeagueStatus] = try await client
            .from("public_league_entries")
            .select("division,opted_in")
            .execute()
            .value

        return rows.first
    }

    func currentPublicLeague() async throws -> PublicLeagueCurrent {
        let rows: [PublicLeagueCurrent]

        do {
            rows = try await client
                .rpc("public_league_current")
                .execute()
                .value
        } catch {
            if let failure = PublicLeagueFailure.from(serverMessage: String(describing: error)) {
                throw failure
            }
            throw PublicLeagueFailure.unknown
        }

        // The function returns exactly one row; an empty one would be a server
        // contract break, not a user-facing failure worth its own copy.
        guard let current = rows.first else {
            throw PublicLeagueFailure.unknown
        }
        return current
    }

    func publicLeagueRanking() async throws -> [PublicLeagueRankingRow] {
        let rows: [PublicLeagueRankingRow] = try await client
            .rpc("public_league_ranking")
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
