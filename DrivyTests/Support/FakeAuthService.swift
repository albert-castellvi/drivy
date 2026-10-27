import Foundation
@testable import Drivy

/// Test double for the Supabase auth boundary: no network, fully inspectable.
final class FakeAuthService: AuthServicing {

    enum FakeError: Error, Equatable {
        case notConfigured
        case network
    }

    var restoredUser: UserSummary?
    var signInOutcome: Result<UserSummary, Error> = .failure(FakeError.notConfigured)
    var signOutError: Error?

    private(set) var restoreCallCount = 0
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0
    private(set) var lastIdToken: String?
    private(set) var lastRawNonce: String?

    func restoreSession() async -> UserSummary? {
        restoreCallCount += 1
        return restoredUser
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> UserSummary {
        signInCallCount += 1
        lastIdToken = idToken
        lastRawNonce = rawNonce
        return try signInOutcome.get()
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let error = signOutError {
            throw error
        }
    }
}
