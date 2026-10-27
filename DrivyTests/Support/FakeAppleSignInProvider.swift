import Foundation
@testable import Drivy

/// Test double for the native Apple sheet: stays suspended until the test
/// resumes it, so in-flight states can be asserted deterministically.
@MainActor
final class FakeAppleSignInProvider: AppleSignInProviding {

    private(set) var requestCount = 0
    var onRequestStarted: (() -> Void)?

    private var pending: CheckedContinuation<AppleCredential, Error>?

    func requestCredential() async throws -> AppleCredential {
        requestCount += 1
        onRequestStarted?()

        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
        }
    }

    func complete(with credential: AppleCredential) {
        pending?.resume(returning: credential)
        pending = nil
    }

    func fail(with error: Error) {
        pending?.resume(throwing: error)
        pending = nil
    }
}
