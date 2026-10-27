import Foundation
@testable import Drivy

/// Test double for the CoreLocation boundary: no device, no permission prompt.
final class FakeLocationSampler: LocationSampling {

    var onSample: ((LocationSample) -> Void)?

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
}
