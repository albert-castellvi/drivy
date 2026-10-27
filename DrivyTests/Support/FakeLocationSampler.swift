import CoreLocation
import Foundation
@testable import Drivy

/// Test double for the CoreLocation boundary: no device, no permission prompt.
final class FakeLocationSampler: LocationSampling {

    var onSample: ((LocationSample) -> Void)?

    var onCoordinate: ((CLLocationCoordinate2D) -> Void)?

    var isDenied = false

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    /// Pushes fixes as CoreLocation would, on the main thread.
    func emit(_ samples: [LocationSample]) {
        samples.forEach { onSample?($0) }
    }

    /// Pushes route coordinates as CoreLocation would, on the main thread.
    func emit(coordinates: [CLLocationCoordinate2D]) {
        coordinates.forEach { onCoordinate?($0) }
    }

    /// Constant-speed drive in 10 s steps; the default is 10 m/s for 100 s = 1 km.
    static func constantDrive(
        speed: Double = 10,
        duration: TimeInterval = 100,
        step: TimeInterval = 10,
        speedLimitKmh: Double? = nil
    ) -> [LocationSample] {
        var samples: [LocationSample] = []
        var time: TimeInterval = 0
        while time <= duration + 1e-9 {
            samples.append(
                LocationSample(
                    timestamp: time,
                    speedMetersPerSecond: speed,
                    speedLimitKmh: speedLimitKmh
                )
            )
            time += step
        }
        return samples
    }

    /// A straight line of `count` points separated by `step` degrees, used to assert
    /// the route the recorder exposes (L11).
    static func straightRoute(
        count: Int,
        latitude: Double = 41.3874,
        longitude: Double = 2.1686,
        step: Double = 0.001
    ) -> [CLLocationCoordinate2D] {
        (0..<count).map { index in
            CLLocationCoordinate2D(
                latitude: latitude + Double(index) * step,
                longitude: longitude + Double(index) * step
            )
        }
    }
}
