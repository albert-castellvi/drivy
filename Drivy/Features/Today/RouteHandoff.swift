import CoreLocation
import Foundation

/// Hands the route of a finished drive to the in-memory route store (L11).
///
/// The raw samples never leave the device (S10), so a drive is only drawable while
/// the app that recorded it is still alive. The recorder publishes the coordinates
/// of the finished drive together with `lastCompletedDrive`; this is the single
/// place that decides whether they are worth storing, which is what makes the
/// handoff testable without SwiftUI.
enum RouteHandoff {

    /// Fewer points than this cannot be drawn as a line, so the detail screen must
    /// keep showing its "no route on this device" state instead.
    static let minimumDrawablePoints = 2

    /// Stores the route under the drive's start timestamp, the key both the
    /// recorder and the stored row agree on. Returns `true` when a drawable track
    /// was stored.
    @discardableResult
    static func store(
        coordinates: [CLLocationCoordinate2D],
        startedAt: Date,
        in store: LocalRouteStore = .shared
    ) -> Bool {
        guard coordinates.count >= minimumDrawablePoints else { return false }

        store.store(DriveTrack(coordinates: coordinates), forStartedAt: startedAt)
        return true
    }
}
