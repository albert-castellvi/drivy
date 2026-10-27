import Combine
import Foundation

/// State of the public leagues switch of the Ajustes tab (S5).
///
/// The switch is the same opt-in the invitation card of the Ligas tab writes:
/// both go through `public.set_public_league_opt_in`, so there is one source of
/// truth and no way for the two screens to disagree.
@MainActor
final class PublicLeagueSettingsViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let loadFailureMessage = "No hemos podido cargar tu participación en las ligas públicas."
    static let saveFailureMessage = "No hemos podido guardar el cambio. Inténtalo de nuevo."

    /// Switch position. `false` also covers "never decided": no row in
    /// `public_league_entries` plays no public league.
    @Published private(set) var isEnabled = false

    @Published private(set) var isLoading = false

    @Published private(set) var isSaving = false

    @Published private(set) var errorMessage: String?

    private let repository: LeaguesDataLoading

    init(repository: LeaguesDataLoading = SupabaseLeaguesRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let status = try await repository.publicLeagueStatus()
            isEnabled = status?.optedIn ?? false
        } catch {
            errorMessage = Self.loadFailureMessage
        }
    }

    /// Stores the decision. The switch follows the tap at once and snaps back if
    /// the server refuses, so an optimistic UI never hides a failed write.
    /// Returns true when the backend kept the new value.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        errorMessage = nil

        let previous = isEnabled
        isEnabled = on
        isSaving = true
        defer { isSaving = false }

        do {
            try await repository.setPublicLeagueOptIn(on)
            return true
        } catch {
            isEnabled = previous
            errorMessage = Self.saveFailureMessage
            return false
        }
    }
}
