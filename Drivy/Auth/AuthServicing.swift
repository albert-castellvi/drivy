import Foundation

/// Boundary between the view model and the backend, so auth state transitions
/// can be tested with a fake (no network, no Supabase client).
protocol AuthServicing {
    /// Returns the user of a persisted session, or `nil` when signed out.
    func restoreSession() async -> UserSummary?

    /// Exchanges a native Apple identity token for a Supabase session.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> UserSummary

    func signOut() async throws
}

/// Boundary between the view model and the native Sign in with Apple flow.
@MainActor
protocol AppleSignInProviding {
    /// Presents the system Apple sheet and returns the credential.
    func requestCredential() async throws -> AppleCredential
}
