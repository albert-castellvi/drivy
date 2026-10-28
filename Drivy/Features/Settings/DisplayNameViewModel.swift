import Combine
import Foundation

/// State of the "Nombre visible" field of Ajustes (S2).
///
/// What a stranger reads in a league ranking is `profiles.display_name`, so the
/// screen shows the stored value, validates the edit with the same rule the
/// database enforces and only then writes it. The name is a pseudonym by
/// default (`handle_new_user`), and editing it is the user's rectification right:
/// there is no other way to change what the leagues show.
@MainActor
final class DisplayNameViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let loadFailureMessage = "No hemos podido cargar tu nombre visible."
    static let saveFailureMessage = "No hemos podido guardar tu nombre visible. Inténtalo de nuevo."

    /// Name stored on the server; `nil` until it has been read.
    @Published private(set) var displayName: String?

    /// What the editor holds. `save` writes this, trimmed and validated.
    @Published var draft = ""

    @Published private(set) var isLoading = false

    @Published private(set) var isSaving = false

    /// Validation error of the field, or the failure of the last load/save.
    @Published private(set) var errorMessage: String?

    private let repository: ProfileDataLoading

    init(repository: ProfileDataLoading = SupabaseProfileRepository()) {
        self.repository = repository
    }

    /// Reads the name of the session's user and seeds the editor with it.
    func load(userID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let name = try await repository.displayName(userID: userID)
            displayName = name
            draft = name
        } catch {
            errorMessage = Self.loadFailureMessage
        }
    }

    /// Validates the draft and, when it passes, writes it.
    /// Returns true when the backend kept the new name.
    @discardableResult
    func save(userID: String) async -> Bool {
        errorMessage = nil

        switch DisplayNameRule.validate(draft) {
        case .invalid(let message):
            errorMessage = message
            return false
        case .valid(let name):
            return await write(name, userID: userID)
        }
    }

    /// Puts the editor back to the stored name and forgets the last error, so a
    /// cancelled edit does not leak into the next one.
    func resetDraft() {
        draft = displayName ?? ""
        errorMessage = nil
    }

    // MARK: - Write

    private func write(_ name: String, userID: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            try await repository.updateDisplayName(name, userID: userID)
            // The stored value only moves once the server accepted it: an
            // optimistic name would show a name the leagues cannot read.
            displayName = name
            draft = name
            return true
        } catch {
            errorMessage = Self.saveFailureMessage
            return false
        }
    }
}
