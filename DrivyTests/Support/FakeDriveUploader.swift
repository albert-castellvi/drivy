import Foundation
@testable import Drivy

/// Test double for the Supabase upload boundary: records what would be sent.
final class FakeDriveUploader: DriveUploading {

    enum FakeError: Error, Equatable {
        case network
        case sessionUnavailable
    }

    private(set) var uploadedRecords: [DriveRecord] = []

    /// Error thrown by every upload while set.
    var error: Error?

    /// Session user returned by `currentSessionUserID()`; `nil` models a session
    /// that cannot be resolved (signed out / expired).
    var sessionUserID: String? = "session-user"

    /// Ids the fake already has stored, modelling rows the server kept from an
    /// earlier attempt (D4): uploading one of these drives succeeds without
    /// storing it again.
    var storedIDs: Set<UUID> = []

    /// Drives whose upload fails with `error` (or `network`), so tests can make
    /// exactly one pending record fail mid-drain.
    var failingIDs: Set<UUID> = []

    func upload(_ record: DriveRecord) async throws {
        if let error {
            throw error
        }
        if failingIDs.contains(record.id) {
            throw error ?? FakeError.network
        }
        // The server already has this drive: the idempotent insert ignores it.
        if storedIDs.contains(record.id) {
            return
        }
        storedIDs.insert(record.id)
        uploadedRecords.append(record)
    }

    func currentSessionUserID() async throws -> String {
        guard let sessionUserID else {
            throw FakeError.sessionUnavailable
        }
        return sessionUserID
    }
}
