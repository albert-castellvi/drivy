import Foundation
import Supabase

/// Supabase implementation of `AuthServicing`.
///
/// Sessions live in the Keychain through supabase-swift's default storage, so
/// the app stays signed in across launches without any custom code:
/// `client.auth.session` reads the persisted session and refreshes it only when
/// it has expired.
struct SupabaseAuthService: AuthServicing {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func restoreSession() async -> UserSummary? {
        do {
            let session = try await client.auth.session
            return UserSummary(session: session)
        } catch {
            // No session in storage, or it could not be refreshed: signed out.
            return nil
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> UserSummary {
        let credentials = OpenIDConnectCredentials(
            provider: .apple,
            idToken: idToken,
            nonce: rawNonce
        )
        let session = try await client.auth.signInWithIdToken(credentials: credentials)
        return UserSummary(session: session)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}

private extension UserSummary {

    init(session: Session) {
        self.init(id: session.user.id.uuidString, email: session.user.email)
    }
}
