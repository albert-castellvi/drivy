import Combine
import Foundation

/// State of the Ligas tab (S7): the user's leagues, creation and join by code.
@MainActor
final class LeaguesViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let loadFailureMessage = "No hemos podido cargar tus ligas. Desliza para reintentar."
    static let createFailureMessage = "No hemos podido crear la liga. Inténtalo de nuevo."
    static let emptyNameMessage = "Ponle un nombre a tu liga."
    static let invalidCodeMessage = "El código de invitación tiene 8 caracteres y no lleva ni O ni I."

    /// `leagues.name` accepts 1…60 characters (schema check of T1).
    static let maximumNameLength = 60

    @Published private(set) var leagues: [LeagueRecord] = []

    @Published private(set) var isLoading = false

    @Published private(set) var isCreating = false

    @Published private(set) var isJoining = false

    @Published private(set) var errorMessage: String?

    @Published private(set) var createErrorMessage: String?

    @Published private(set) var joinErrorMessage: String?

    private let repository: LeaguesDataLoading

    init(repository: LeaguesDataLoading = SupabaseLeaguesRepository()) {
        self.repository = repository
    }

    // MARK: - Loading

    func load(userID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            leagues = try await repository.leagues(userID: userID)
        } catch {
            errorMessage = Self.loadFailureMessage
        }

        isLoading = false
    }

    // MARK: - Creation

    /// Creates the league and joins it as its first member; the server draws its
    /// eight-symbol invite code in the same call (S3), so creation cannot pick a
    /// code a client could guess. Returns true when the league exists in the
    /// backend afterwards.
    ///
    /// `access` is the S9 snapshot of the plan in force: a free account belongs to at
    /// most one league, so the call is refused before touching the backend. `nil`
    /// (plan still unknown) never blocks.
    ///
    /// The server enforces the same cap (S5.1): when `create_league` raises
    /// `league_limit`, the copy is exactly the one the client gate shows (S5.3).
    @discardableResult
    func createLeague(
        name: String,
        access: FreemiumAccess? = nil
    ) async -> Bool {
        createErrorMessage = nil

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            createErrorMessage = Self.emptyNameMessage
            return false
        }

        guard !isLeagueLimitReached(access: access) else {
            createErrorMessage = LeagueLimitGate.limitMessage
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let league = try await repository.createLeague(
                name: String(trimmed.prefix(Self.maximumNameLength))
            )
            leagues.insert(league, at: 0)
            return true
        } catch LeagueJoinFailure.leagueLimit {
            createErrorMessage = LeagueLimitGate.limitMessage
            return false
        } catch {
            createErrorMessage = Self.createFailureMessage
            return false
        }
    }

    // MARK: - Join

    /// Joins a league with the code (or the whole invite link). The member cap and
    /// the hourly attempt limit are enforced by `public.join_league_by_code` (S3),
    /// so its answers are what the UI translates. Returns true when the user is a
    /// member afterwards.
    ///
    /// The input is checked locally first: a code that cannot exist would only
    /// spend one of the ten attempts allowed per hour.
    ///
    /// `access` is the S9 snapshot: the free plan's one-league cap is enforced here
    /// so the RPC is not even called. `nil` (plan still unknown) never blocks.
    /// The server enforces the same cap (S5.1): a raised `league_limit` reaches the
    /// join path through `LeagueJoinFailure.leagueLimit`, whose message is the
    /// client-gate copy (S5.3).
    @discardableResult
    func joinLeague(code: String, userID: String, access: FreemiumAccess? = nil) async -> Bool {
        joinErrorMessage = nil

        let normalized = LeagueInviteLink.code(fromUserInput: code)
        guard LeagueInviteCode.isValid(normalized) else {
            joinErrorMessage = Self.invalidCodeMessage
            return false
        }

        guard !isLeagueLimitReached(access: access) else {
            joinErrorMessage = LeagueLimitGate.limitMessage
            return false
        }

        isJoining = true
        defer { isJoining = false }

        do {
            _ = try await repository.joinLeague(inviteCode: normalized)
            // Reloading is what makes the new league, and its ranking, visible.
            await load(userID: userID)
            return true
        } catch let failure as LeagueJoinFailure {
            joinErrorMessage = failure.message
            return false
        } catch {
            joinErrorMessage = LeagueJoinFailure.unknown.message
            return false
        }
    }

    // MARK: - Freemium cap (S9)

    /// Whether the plan in force blocks another league. Kept on the view model so
    /// the view and the create/join guards share one implementation.
    func isLeagueLimitReached(access: FreemiumAccess?) -> Bool {
        LeagueLimitGate.isAtLimit(access: access, leagueCount: leagues.count)
    }
}
