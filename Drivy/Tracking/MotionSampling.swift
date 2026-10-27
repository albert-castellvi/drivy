import CoreMotion
import Foundation

/// Boundary between the drive recorder and CoreMotion.
protocol MotionSampling: AnyObject {

    /// Called on the main queue for every accepted reading.
    var onSample: ((MotionSample) -> Void)? { get set }

    func start()

    func stop()
}

/// `CMMotionManager` wrapper: gives the scoring engine the longitudinal
/// acceleration it needs for harsh braking and harsh acceleration (S5).
final class CoreMotionSampler: MotionSampling {

    var onSample: ((MotionSample) -> Void)?

    private let motionManager: CMMotionManager

    /// 10 Hz is plenty for events that last tenths of a second, and it is far
    /// cheaper than the 100 Hz maximum.
    private let updateInterval: TimeInterval = 0.1

    init(motionManager: CMMotionManager = CMMotionManager()) {
        self.motionManager = motionManager
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.onSample?(
                MotionSample(
                    // Device motion timestamps are seconds since boot: a
                    // monotonic scale local to this stream, which the recorder
                    // rebases like the location one.
                    timestamp: motion.timestamp,
                    longitudinalAcceleration: Self.longitudinalAcceleration(of: motion)
                )
            )
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    /// Longitudinal (forward/backward) acceleration in m/s², positive when
    /// speeding up and negative when braking.
    ///
    /// v1 assumption: the phone sits in a portrait car mount with the top of the
    /// screen pointing forward, so the device +y axis is the car's forward axis.
    /// A heading-independent projection (GPS course + attitude) is deliberately
    /// out of scope: it needs a calibration step the MVP does not have yet.
    private static func longitudinalAcceleration(of motion: CMDeviceMotion) -> Double {
        motion.userAcceleration.y
    }
}
