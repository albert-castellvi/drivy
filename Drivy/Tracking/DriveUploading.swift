import Foundation

/// Boundary between the drive recorder and the backend, so the recorder can be
/// tested without a network.
protocol DriveUploading {

    /// Uploads the summarized row of one finished drive (S10). Raw GPS/motion
    /// samples are never part of the payload.
    ///
    /// D4: the upload is idempotent — the row carries the client-generated
    /// `DriveRecord.id` as the `drives.id` primary key, and an insert that hits
    /// an already stored id is a success (the drive is already there), never a
    /// second row nor a permanent failure.
    func upload(_ record: DriveRecord) async throws

    /// D4: id of the signed-in user of the current session, or a thrown error
    /// when the session cannot be resolved. `DriveRecorder` stores it with each
    /// pending upload, so a drive recorded by user A is never uploaded into
    /// user B's account after a sign-out and a new sign-in.
    func currentSessionUserID() async throws -> String
}
