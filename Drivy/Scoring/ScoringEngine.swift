import Foundation

/// Scoring v1 (S5, S13): turns the injected samples of one drive into a 0–100
/// score.
///
/// ```
/// eventsPerKm  = eventCount / max(distanceKm, ScoringRules.minimumDistanceKm)
/// penalty      = Σ (eventCount × weightPerKm) / effectiveKm
///                − phone use is excluded when connected mode is on (S13)
/// raw          = 100 − penalty (+ connectedModeBonus when connected)
/// score        = clamp(round(raw), 0, 100)
/// ```
///
/// The type is stateless and imports nothing but Foundation: no CoreLocation,
/// no CoreMotion, no AVFoundation. All device interaction lives in
/// `Drivy/Tracking`, which feeds it `DriveSamples`.
struct ScoringEngine {

    /// Returns `nil` when the drive has no location samples at all: there is
    /// nothing to measure, so there is nothing to score (and nothing to upload).
    func score(_ samples: DriveSamples) -> DriveScore? {
        guard let first = samples.locations.first, let last = samples.locations.last else {
            return nil
        }

        let distanceKm = distanceMeters(samples.locations) / 1000
        let durationSeconds = max(0, last.timestamp - first.timestamp)

        let harshBrakes = countEvents(
            in: samples.motions,
            exceeds: { $0 < -ScoringRules.harshBrakingThreshold },
            isReleased: { $0 > -ScoringRules.harshBrakingReleaseThreshold }
        )
        let harshAccelerations = countEvents(
            in: samples.motions,
            exceeds: { $0 > ScoringRules.harshAccelerationThreshold },
            isReleased: { $0 < ScoringRules.harshAccelerationReleaseThreshold }
        )
        let phoneUseEvents = max(0, samples.phoneUseEvents)
        let speedingEvents = countSpeedingEvents(in: samples.locations)

        let finalScore = points(
            distanceKm: distanceKm,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: samples.connectedMode
        )

        return DriveScore(
            score: finalScore,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: samples.connectedMode
        )
    }

    // MARK: - Points

    /// Penalties are cumulative and weighted per km (S5); connected mode adds
    /// its bonus and waives the phone-use penalty (S13).
    private func points(
        distanceKm: Double,
        harshBrakes: Int,
        harshAccelerations: Int,
        phoneUseEvents: Int,
        speedingEvents: Int,
        connectedMode: Bool
    ) -> Int {
        let effectiveKm = max(distanceKm, ScoringRules.minimumDistanceKm)

        var penalty = 0.0
        penalty += Double(harshBrakes) * ScoringRules.harshBrakingPenaltyPerKm / effectiveKm
        penalty += Double(harshAccelerations) * ScoringRules.harshAccelerationPenaltyPerKm / effectiveKm
        penalty += Double(speedingEvents) * ScoringRules.speedingPenaltyPerKm / effectiveKm
        if !connectedMode {
            penalty += Double(phoneUseEvents) * ScoringRules.phoneUsePenaltyPerKm / effectiveKm
        }

        var raw = 100 - penalty
        if connectedMode {
            raw += ScoringRules.connectedModeBonus
        }

        return min(max(Int(raw.rounded()), 0), 100)
    }

    // MARK: - Distance

    /// Trapezoidal integration of the GPS speed over time. A CLLocation speed
    /// of −1 means "unknown", so negative values are clamped instead of
    /// subtracting distance.
    private func distanceMeters(_ locations: [LocationSample]) -> Double {
        guard locations.count > 1 else { return 0 }

        var meters = 0.0
        for (previous, current) in zip(locations, locations.dropFirst()) {
            let seconds = max(0, current.timestamp - previous.timestamp)
            let previousSpeed = max(0, previous.speedMetersPerSecond)
            let currentSpeed = max(0, current.speedMetersPerSecond)
            meters += (previousSpeed + currentSpeed) / 2 * seconds
        }
        return meters
    }

    // MARK: - Events

    /// Counts how many separate times the signal crosses into an event.
    ///
    /// An event stays open until `isReleased` is true, so a hard brake sampled
    /// at 50 Hz is one event, while a real second brake (signal back down to
    /// normal in between) is two.
    private func countEvents(
        in motions: [MotionSample],
        exceeds: (Double) -> Bool,
        isReleased: (Double) -> Bool
    ) -> Int {
        var count = 0
        var isActive = false

        for motion in motions {
            let acceleration = motion.longitudinalAcceleration
            if isActive {
                if isReleased(acceleration) {
                    isActive = false
                }
            } else if exceeds(acceleration) {
                isActive = true
                count += 1
            }
        }
        return count
    }

    /// An over-speed event starts when the speed passes limit + 10 km/h and
    /// stays open until the speed drops 3 km/h below that threshold. A fix with
    /// no known limit cannot be judged, and it closes any open event because the
    /// comparison baseline changed.
    private func countSpeedingEvents(in locations: [LocationSample]) -> Int {
        var count = 0
        var isActive = false

        for location in locations {
            guard let limitKmh = location.speedLimitKmh else {
                isActive = false
                continue
            }

            let threshold = (limitKmh + ScoringRules.speedingToleranceKmh) / 3.6
            let release = threshold - ScoringRules.speedingReleaseKmh / 3.6
            let speed = max(0, location.speedMetersPerSecond)

            if isActive {
                if speed <= release {
                    isActive = false
                }
            } else if speed > threshold {
                isActive = true
                count += 1
            }
        }
        return count
    }
}
