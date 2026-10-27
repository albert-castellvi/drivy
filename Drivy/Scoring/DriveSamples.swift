import Foundation

/// One GPS fix, reduced to what the score depends on.
///
/// `timestamp` is measured in seconds on any monotonic scale shared by every
/// sample of the drive: the engine only uses differences, so it never needs a
/// wall clock and stays deterministic in tests.
struct LocationSample: Equatable {

    let timestamp: TimeInterval

    let speedMetersPerSecond: Double

    /// Posted speed limit for this fix, when it is known. It is optional on
    /// purpose: without road data the tracker has no limit to compare against
    /// and the speeding rule simply has nothing to judge.
    let speedLimitKmh: Double?
}

/// One device-motion reading on the vehicle's longitudinal axis.
///
/// Positive means the car is speeding up, negative means it is braking; that is
/// the same sign convention CoreMotion reports for `userAcceleration` along the
/// vehicle axis (see `CoreMotionSampler`).
struct MotionSample: Equatable {

    let timestamp: TimeInterval

    let longitudinalAcceleration: Double
}

/// Everything the scoring engine needs to score one drive.
///
/// The engine never touches CoreLocation, CoreMotion or AVFoundation: it only
/// consumes these injected samples, which is what makes the whole scoring layer
/// unit-testable without a device.
struct DriveSamples: Equatable {

    var locations: [LocationSample] = []

    var motions: [MotionSample] = []

    /// "unlock/interacción durante conducción" events collected while driving.
    var phoneUseEvents: Int = 0

    /// Connected driving detected through the audio route (S13).
    var connectedMode: Bool = false
}
