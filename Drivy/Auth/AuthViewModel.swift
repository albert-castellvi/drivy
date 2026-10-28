import Combine
import Foundation

/// Owns the authentication state machine of the shell.
///
/// The auth and Apple dependencies are protocols, and crash reporting is a
/// pair of closures, so the whole flow can be exercised in unit tests without a
/// network, an Apple sheet or a started Sentry SDK.
@MainActor
final class AuthViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let signInFailureMessage = "No hemos podido iniciar sesión. Inténtalo de nuevo."
    static let signOutFailureMessage = "No hemos podido cerrar sesión. Inténtalo de nuevo."

    @Published private(set) var state: AuthState = .restoring

    private let authService: AuthServicing
    private let appleSignInProvider: AppleSignInProviding
    /// Crash reporting, injected so tests can assert what was reported (S4).
    /// It only ever receives a `CrashReport`, never the upstream error (S5).
    private let reportError: (Error) -> Void
    private let setReportedUser: (String?) -> Void
    private var didRestoreSession = false

    init(
        authService: AuthServicing = SupabaseAuthService(),
        appleSignInProvider: AppleSignInProviding? = nil,
        reportError: @escaping (Error) -> Void = CrashReporting.capture,
        setReportedUser: @escaping (String?) -> Void = CrashReporting.setUser
    ) {
        self.authService = authService
        // Default arguments are evaluated in a nonisolated context, and
        // AppleSignInCoordinator is @MainActor (ASAuthorization delegate
        // callbacks), so the real default is built here instead.
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInCoordinator()
        self.reportError = reportError
        self.setReportedUser = setReportedUser
    }

    var signedInUser: UserSummary? {
        state.user
    }

    /// Called once when the shell appears: reads the persisted session.
    /// Idempotent, so a re-created scene does not restart the flow.
    func restoreSession() async {
        guard !didRestoreSession else { return }
        didRestoreSession = true

        state = .restoring
        if let user = await authService.restoreSession() {
            state = .signedIn(user)
            setReportedUser(user.id)
        } else {
            state = .signedOut
        }
    }

    /// Tapping the Apple button while a request is already in flight is a
    /// no-op, so a double tap cannot open two sheets.
    func signInWithApple() async {
        guard state != .authenticating else { return }

        state = .authenticating
        do {
            let credential = try await appleSignInProvider.requestCredential()
            let user = try await authService.signInWithApple(
                idToken: credential.idToken,
                rawNonce: credential.rawNonce
            )
            state = .signedIn(user)
            setReportedUser(user.id)
        } catch AppleSignInError.cancelled {
            // Dismissing the sheet is not an error worth showing, nor worth
            // reporting: the user did exactly what they meant to.
            state = .signedOut
        } catch {
            reportError(Self.reportedFailure(for: error))
            state = .failed(message: Self.signInFailureMessage)
        }
    }

    func signOut() async {
        do {
            try await authService.signOut()
            state = .signedOut
            setReportedUser(nil)
        } catch {
            reportError(CrashReport.authSignOutFailed)
            state = .failed(message: Self.signOutFailureMessage)
        }
    }

    // MARK: - Crash reporting (S5)

    /// Sanitized code of a failed sign-in.
    ///
    /// The Apple sheet and the token exchange are told apart because they fail
    /// for different reasons on the dashboard, but neither the `AuthError` nor
    /// the `ASAuthorizationError` description is forwarded: both can name the
    /// account or the raw response body.
    private static func reportedFailure(for error: Error) -> CrashReport {
        if error is AppleSignInError {
            return .appleSignInFailed
        }
        return .authSignInFailed
    }
}
