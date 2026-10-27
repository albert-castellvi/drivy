import Combine
import Foundation

/// State of the Ligas tab (S7): the user's leagues, creation and join by code.
@MainActor
final class LeaguesViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let loadFailureMessage = "No hemos podido cargar tus ligas. Desliza para reintentar."
    static let createFailureMessage = "No hemos podido crear la liga. Inténtalo de nuevo."
    static let emptyNameMessage = "Ponle un nombre a tu liga."
    static let invalidCodeMessage = "El código de invitación tiene 6 caracteres."

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
    private let inviteCodeGenerator: () -> String

    init(
        repository: LeaguesDataLoading = SupabaseLeaguesRepository(),
        inviteCodeGenerator: @escaping () -> String = { LeagueInviteCode.generate() }
    ) {
        self.repository = repository
        self.inviteCodeGenerator = inviteCodeGenerator
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

    /// Creates the league and joins it as its first member. Returns true when the
    /// league exists in the backend afterwards.
    @discardableResult
    func createLeague(name: String, userID: String) async -> Bool {
        createErrorMessage = nil

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            createErrorMessage = Self.emptyNameMessage
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let league = try await repository.createLeague(
                name: String(trimmed.prefix(Self.maximumNameLength)),
                inviteCode: inviteCodeGenerator(),
                userID: userID
            )
            leagues.insert(league, at: 0)
            return true
        } catch {
            createErrorMessage = Self.createFailureMessage
            return false
        }
    }

    // MARK: - Join

    /// Joins a league with the code (or the whole invite link). The member cap is
    /// enforced by `public.join_league_by_code`, so its failures are what the UI
    /// translates. Returns true when the user is a member afterwards.
    @discardableResult
    func joinLeague(code: String, userID: String) async -> Bool {
        joinErrorMessage = nil

        let normalized = LeagueInviteLink.code(fromUserInput: code)
        guard normalized.count == LeagueInviteCode.length else {
            joinErrorMessage = Self.invalidCodeMessage
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
}
