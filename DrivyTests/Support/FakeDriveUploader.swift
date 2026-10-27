import Foundation
@testable import Drivy

/// Test double for the Supabase upload boundary: records what would be sent.
final class FakeDriveUploader: DriveUploading {

    enum FakeError: Error, Equatable {
        case network
    }

    private(set) var uploadedRecords: [DriveRecord] = []
    var error: Error?

    func upload(_ record: DriveRecord) async throws {
        if let error {
            throw error
        }
        uploadedRecords.append(record)
    }
}
