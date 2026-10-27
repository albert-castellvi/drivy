import Foundation

/// Boundary between the drive recorder and the backend, so the recorder can be
/// tested without a network.
protocol DriveUploading {

    /// Uploads the summarized row of one finished drive (S10). Raw GPS/motion
    /// samples are never part of the payload.
    func upload(_ record: DriveRecord) async throws
}
