import Foundation
@testable import Drivy

/// Test double for the Supabase boundary of the visible name (S2): no network.
final class FakeProfileDataLoader: ProfileDataLoading {

    enum FakeError: Error, Equatable {
        case network
        case notConfigured
    }

    /// Answer of `displayName(userID:)`.
    var displayNameResult: Result<String, Error> = .failure(FakeError.notConfigured)

    /// When set, `updateDisplayName` throws it.
    var updateError: Error?

    private(set) var displayNameCallCount = 0
    private(set) var displayNameCalls: [String] = []
    private(set) var updateCalls: [(name: String, userID: String)] = []

    func displayName(userID: String) async throws -> String {
        displayNameCallCount += 1
        displayNameCalls.append(userID)
        return try displayNameResult.get()
    }

    func updateDisplayName(_ name: String, userID: String) async throws {
        updateCalls.append((name, userID))
        if let updateError = updateError {
            throw updateError
        }
    }
}
