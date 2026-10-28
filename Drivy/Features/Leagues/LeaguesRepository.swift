import Foundation
import Supabase

/// Boundary between the Ligas screens and the backend (S7), so creation, join and
/// ranking are tested without a network.
protocol LeaguesDataLoading {

    func leagues(userID: String) async throws -> [LeagueRecord]

    /// Calls `public.create_league(p_name)`, which creates the league, draws its
    /// eight-symbol invite code and makes the caller its first member in one step
    /// (S3). Direct inserts into `leagues`/`league_members` are rejected by RLS.
    func createLeague(name: String) async throws -> LeagueRecord

    /// Calls `public.join_league_by_code`, which enforces the 25-member cap and
    /// the hourly attempt limit, and returns the league id or `nil` for an unknown
    /// code and for a full league alike (S3). Failures are thrown as
    /// `LeagueJoinFailure`.
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

/// Server-side answers of `public.join_league_by_code` (S3) plus the copy the UI
/// shows for them.
///
/// The RPC answers `null` for an unknown code and for a full league alike, so the
/// client cannot tell the two apart and neither can the person probing codes.
enum LeagueJoinFailure: Error, Equatable {

    /// The RPC returned no league id: the code does not exist, or the league is
    /// already full (S3).
    case unavailable

    /// Ten failed attempts in an hour: the RPC raises `too_many_attempts` (S3).
    case tooManyAttempts

    /// The caller is in one league already and has no active premium: the RPCs
    /// raise `league_limit` (S5.1). The copy is the same the client gate shows,
    /// so the paywall sentence is defined in exactly one place (S5.3).
    case leagueLimit

    case unknown

    var message: String {
        switch self {
        case .unavailable:
            return "Ese código no sirve: no existe o la liga ya está completa."
        case .tooManyAttempts:
            return "Demasiados intentos. Prueba de nuevo dentro de una hora."
        case .leagueLimit:
            return LeagueLimitGate.limitMessage
        case .unknown:
            return "No hemos podido unirte a la liga. Inténtalo de nuevo."
        }
    }

    /// The RPCs raise bare exception strings, so they reach the client inside the
    /// PostgREST error message (with the SQLSTATE prefix in front).
    static func from(serverMessage message: String) -> LeagueJoinFailure? {
        let normalized = message.lowercased()

        if normalized.contains("too_many_attempts") {
            return .tooManyAttempts
        }
        if normalized.contains("league_limit") {
            return .leagueLimit
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
    /// The RPC worked but PostgREST returned no row to read the league from.
    case emptyResult
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

    func createLeague(name: String) async throws -> LeagueRecord {
        // One RPC instead of two inserts: the function draws the invite code and
        // adds the caller as a member, which is what keeps both out of reach of a
        // modified client (S3).
        let rows: [LeagueRecord]

        do {
            rows = try await client
                .rpc("create_league", params: ["p_name": name])
                .execute()
                .value
        } catch {
            // The free one-league cap is enforced by the RPC (S5.1); the raised
            // `league_limit` maps to the same failure the join path uses, so the
            // screen shows the paywall copy the client gate runs (S5.3).
            // Everything else keeps its original error.
            if let failure = LeagueJoinFailure.from(serverMessage: String(describing: error)),
               failure == .leagueLimit {
                throw failure
            }
            throw error
        }

        guard let league = rows.first else {
            throw LeagueRepositoryError.emptyResult
        }

        return league
    }

    func joinLeague(inviteCode: String) async throws -> String {
        let code = LeagueInviteCode.normalize(inviteCode)
        let leagueID: String?

        do {
            leagueID = try await client
                .rpc("join_league_by_code", params: ["p_code": code])
                .execute()
                .value
        } catch {
            // The RPC raises bare exception strings, and PostgREST forwards them in
            // the error description: that is enough to map them without depending
            // on the concrete error type of the client library. `league_limit`
            // (S5.1) maps like the rest, to the client-gate copy (S5.3).
            if let failure = LeagueJoinFailure.from(serverMessage: String(describing: error)) {
                throw failure
            }
            throw LeagueJoinFailure.unknown
        }

        // `null` is the RPC's single answer for an unknown code and for a league
        // that is already full (S3): the client must not invent a distinction.
        guard let leagueID else {
            throw LeagueJoinFailure.unavailable
        }

        return leagueID
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
