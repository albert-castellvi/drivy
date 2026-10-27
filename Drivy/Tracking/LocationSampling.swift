import CoreLocation
import Foundation

/// Boundary between the drive recorder and CoreLocation, so the recorder can be
/// tested without a device.
///
/// Timestamps are on the system's monotonic scale (`timeIntervalSinceReferenceDate`):
/// the recorder rebases each stream to its own first sample, so nothing here has
/// to know about the drive start.
protocol LocationSampling: AnyObject {

    /// Called on the main queue for every accepted fix.
    var onSample: ((LocationSample) -> Void)? { get set }

    /// Called on the main queue for every accepted fix, with the coordinate of
    /// that fix (L11).
    ///
    /// The route travels on its own callback instead of inside `LocationSample`:
    /// the scoring input stays free of CoreLocation values (S5 is scored from
    /// speed and motion only) and the coordinates never leave the device (S10),
    /// so they must not leak into the upload path.
    var onCoordinate: ((CLLocationCoordinate2D) -> Void)? { get set }

    /// True when the user refused location access, i.e. no drive can be measured.
    var isDenied: Bool { get }

    func start()

    func stop()
}

/// `CLLocationManager` wrapper used by the MVP (S4: the manual button is the
/// guarantee, auto-detection is best effort).
///
/// Background updates are requested because a drive must keep being recorded
/// with the screen off (S12); the `location` background mode is declared in
/// `Info.plist`.
final class CoreLocationSampler: NSObject, LocationSampling {

    var onSample: ((LocationSample) -> Void)?

    var onCoordinate: ((CLLocationCoordinate2D) -> Void)?

    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        // ~5 m between fixes is enough for distance and speed; a smaller filter
        // would only drain the battery.
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorizedWhenInUse, .authorizedAlways:
            return false
        @unknown default:
            return false
        }
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // The answer arrives in `locationManagerDidChangeAuthorization`.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func startUpdates() {
        // Setting this flag without the background mode in Info.plist raises an
        // exception, so it is checked instead of assumed.
        if backgroundLocationIsDeclared {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    private var backgroundLocationIsDeclared: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }
}

extension CoreLocationSampler: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !isDenied else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // A negative horizontal accuracy means the fix is invalid.
            guard location.horizontalAccuracy >= 0 else { continue }

            onSample?(
                LocationSample(
                    timestamp: location.timestamp.timeIntervalSinceReferenceDate,
                    speedMetersPerSecond: location.speed,
                    // No road data in the MVP, so there is no limit to compare
                    // against yet: the speeding rule (S5) is implemented and
                    // tested in the engine, and the map layer (T4) is what will
                    // start supplying limits here.
                    speedLimitKmh: nil
                )
            )
            // L11: the same accepted fix feeds the on-device route of the drive.
            onCoordinate?(location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best effort (S4): a lost fix must not end the drive.
    }
}
