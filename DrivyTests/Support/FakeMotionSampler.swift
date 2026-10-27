import Foundation
@testable import Drivy

/// Test double for the CoreMotion boundary.
final class FakeMotionSampler: MotionSampling {

    var onSample: ((MotionSample) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ accelerations: [Double], startingAt time: TimeInterval = 0, step: TimeInterval = 1) {
        for (index, acceleration) in accelerations.enumerated() {
            onSample?(
                MotionSample(
                    timestamp: time + TimeInterval(index) * step,
                    longitudinalAcceleration: acceleration
                )
            )
        }
    }
}
