import Foundation

/// The signed-in user, reduced to what the shell needs. Keeping this small
/// lets the auth layer be tested without a Supabase client.
struct UserSummary: Equatable {
    let id: String
    let email: String?

    /// `auth.users.created_at` of the account, the anchor of the 7-day full
    /// history window of the free plan (S9). `nil` when the session does not
    /// carry it, in which case the freemium gate falls back to "now".
    let createdAt: Date?

    init(id: String, email: String?, createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.createdAt = createdAt
    }

    /// Short identifier shown in Ajustes (a full UUID is unusable in a row).
    var shortIdentifier: String {
        String(id.prefix(8))
    }
}

/// UI state of the authentication flow. Every transition is driven by
/// `AuthViewModel` so it can be asserted in unit tests.
enum AuthState: Equatable {
    /// First launch: asking the Keychain whether a session already exists.
    case restoring
    /// No session: the sign-in screen is shown.
    case signedOut
    /// Sign in with Apple sheet is in flight, or the token exchange is running.
    case authenticating
    case signedIn(UserSummary)
    case failed(message: String)

    var user: UserSummary? {
        if case .signedIn(let user) = self {
            return user
        }
        return nil
    }
}

/// Errors surfaced by the native Apple credential step.
enum AppleSignInError: Error, Equatable {
    /// The user dismissed the Apple sheet. Not an error for the user, so the
    /// view model returns to `signedOut` instead of `failed`.
    case cancelled
    /// Apple authorized the request but the identity token was missing.
    case missingIdentityToken
    case failed(String)
}

/// The credential Apple hands back: the identity token for Supabase, plus the
/// raw nonce that was hashed into the request.
struct AppleCredential: Equatable {
    let idToken: String
    let rawNonce: String
}
