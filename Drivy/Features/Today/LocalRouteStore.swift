import CoreLocation
import Foundation

/// In-memory route of one drive (S10).
///
/// Raw GPS samples never leave the device, so a map can only draw a route this
/// device still remembers. Nothing here is persisted and nothing here is uploaded.
struct DriveTrack: Equatable {

    let coordinates: [CLLocationCoordinate2D]

    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
    }

    /// Stable key of a drive's route: its exact start timestamp, which both the
    /// recorder and the stored row agree on without a server round trip.
    static func key(forStartedAt date: Date) -> String {
        DriveISO8601.string(from: date)
    }

    static func == (lhs: DriveTrack, rhs: DriveTrack) -> Bool {
        guard lhs.coordinates.count == rhs.coordinates.count else { return false }
        return zip(lhs.coordinates, rhs.coordinates).allSatisfy { left, right in
            left.latitude == right.latitude && left.longitude == right.longitude
        }
    }
}

/// Keeps the routes of the current launch in memory only.
///
/// This is the single seam a local route needs: `DriveRecorder` (T3) does not
/// expose coordinates yet, so nothing fills this store and the drive detail screen
/// shows the stored summary with an explicit "no route on this device" state
/// instead of drawing an invented line.
final class LocalRouteStore {

    static let shared = LocalRouteStore()

    private(set) var tracks: [String: DriveTrack] = [:]

    func store(_ track: DriveTrack, forStartedAt date: Date) {
        tracks[DriveTrack.key(forStartedAt: date)] = track
    }

    func track(forStartedAt date: Date) -> DriveTrack? {
        tracks[DriveTrack.key(forStartedAt: date)]
    }

    func removeAll() {
        tracks.removeAll()
    }
}
