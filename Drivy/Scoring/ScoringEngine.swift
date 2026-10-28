import Foundation

/// Scoring v1 (S5, S13): turns the injected samples of one drive into a 0–100
/// score, plus the events it counted and, when a route is known, where each one
/// happened (S2).
///
/// ```
/// eventsPerKm  = eventCount / max(distanceKm, ScoringRules.minimumDistanceKm)
/// penalty      = Σ (eventCount × weightPerKm) / effectiveKm
///                − phone use is excluded when connected mode is on (S13)
/// raw          = 100 − penalty (+ connectedModeBonus when connected)
/// score        = clamp(round(raw), 0, 100)
/// ```
///
/// The type is stateless and imports nothing but Foundation: no CoreLocation, no
/// CoreMotion, no AVFoundation. All device interaction lives in
/// `Drivy/Tracking`, which feeds it `DriveSamples`.
struct ScoringEngine {

    /// Returns `nil` when the drive has no location samples at all: there is
    /// nothing to measure, so there is nothing to score (and nothing to upload).
    ///
    /// `route` is the on-device list of coordinates of the same fixes as
    /// `samples.locations`, in the same order (L11: the recorder keeps both). When
    /// it is empty — the live score while driving, a re-score of a stored drive —
    /// the events still carry their place in time but no coordinate. A route never
    /// changes the score, the counts, the thresholds or the weights: it only
    /// locates what was already counted (S2).
    func score(_ samples: DriveSamples, route: [DriveCoordinate] = []) -> DriveScore? {
        guard let first = samples.locations.first, let last = samples.locations.last else {
            return nil
        }

        let distanceKm = distanceMeters(samples.locations) / 1000
        let durationSeconds = max(0, last.timestamp - first.timestamp)

        let harshBrakeEvents = detectEvents(
            kind: .harshBrake,
            in: samples.motions,
            exceeds: { $0 < -ScoringRules.harshBrakingThreshold },
            isReleased: { $0 > -ScoringRules.harshBrakingReleaseThreshold }
        )
        let harshAccelerationEvents = detectEvents(
            kind: .harshAcceleration,
            in: samples.motions,
            exceeds: { $0 > ScoringRules.harshAccelerationThreshold },
            isReleased: { $0 < ScoringRules.harshAccelerationReleaseThreshold }
        )
        let speedingEvents = detectSpeedingEvents(in: samples.locations)
        let phoneUseEvents = max(0, samples.phoneUseEvents)
        // Phone use is a drive-level fact: the samples carry how many times the
        // phone was used, not when (S5), so these events have no position.
        let phoneUseEventList = (0..<phoneUseEvents).map { _ in DriveEvent(kind: .phoneUse) }

        let finalScore = points(
            distanceKm: distanceKm,
            harshBrakes: harshBrakeEvents.count,
            harshAccelerations: harshAccelerationEvents.count,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents.count,
            connectedMode: samples.connectedMode
        )

        let events = ordered(
            positioned(
                harshBrakeEvents + harshAccelerationEvents + speedingEvents + phoneUseEventList,
                in: samples.locations,
                route: route
            )
        )

        return DriveScore(
            score: finalScore,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            harshBrakes: harshBrakeEvents.count,
            harshAccelerations: harshAccelerationEvents.count,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents.count,
            connectedMode: samples.connectedMode,
            events: events
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

    /// Every separate time the signal crosses into an event (S5), stamped with
    /// the timestamp of the sample that crossed (S2).
    ///
    /// An event stays open until `isReleased` is true, so a hard brake sampled at
    /// 50 Hz is one event, while a real second brake (signal back down to normal
    /// in between) is two. The rule is the one the score has always used: the
    /// number of returned events *is* the count, so the two can never drift.
    private func detectEvents(
        kind: DriveEventKind,
        in motions: [MotionSample],
        exceeds: (Double) -> Bool,
        isReleased: (Double) -> Bool
    ) -> [DriveEvent] {
        var events: [DriveEvent] = []
        var isActive = false

        for motion in motions {
            let acceleration = motion.longitudinalAcceleration
            if isActive {
                if isReleased(acceleration) {
                    isActive = false
                }
            } else if exceeds(acceleration) {
                isActive = true
                events.append(DriveEvent(kind: kind, timestamp: motion.timestamp))
            }
        }
        return events
    }

    /// An over-speed event starts when the speed passes limit + 10 km/h and
    /// stays open until the speed drops 3 km/h below that threshold. A fix with
    /// no known limit cannot be judged, and it closes any open event because the
    /// comparison baseline changed.
    ///
    /// Each event is stamped with the fix that opened it (S2), which is also the
    /// fix the map should point at.
    private func detectSpeedingEvents(in locations: [LocationSample]) -> [DriveEvent] {
        var events: [DriveEvent] = []
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
                events.append(DriveEvent(kind: .speeding, timestamp: location.timestamp))
            }
        }
        return events
    }

    /// Attaches the coordinate of the fix nearest in time to each event (S2).
    ///
    /// `route` is index-aligned with `locations`: the recorder appends both from
    /// the same accepted fix (L11), so the nearest fix in time is the nearest
    /// entry of the route. On an exact tie the earlier fix wins, which keeps the
    /// result deterministic.
    private func positioned(
        _ events: [DriveEvent],
        in locations: [LocationSample],
        route: [DriveCoordinate]
    ) -> [DriveEvent] {
        // Without a route (live score, re-score) there is nothing to attach and
        // no work worth doing on every incoming fix.
        guard !route.isEmpty, !locations.isEmpty else { return events }

        return events.map { event in
            guard
                let timestamp = event.timestamp,
                let index = nearestFix(to: timestamp, in: locations),
                index < route.count
            else {
                return event
            }
            return DriveEvent(kind: event.kind, timestamp: timestamp, coordinate: route[index])
        }
    }

    private func nearestFix(to timestamp: TimeInterval, in locations: [LocationSample]) -> Int? {
        var bestIndex: Int?
        var bestDistance = TimeInterval.infinity

        for (index, location) in locations.enumerated() {
            let distance = abs(location.timestamp - timestamp)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Time order, then the fixed kind order for events counted on the same fix,
    /// so a debrief or a test never depends on the order of the detection passes.
    /// Events without a position in time go last.
    private func ordered(_ events: [DriveEvent]) -> [DriveEvent] {
        events.sorted { left, right in
            let leftTime = left.timestamp ?? TimeInterval.infinity
            let rightTime = right.timestamp ?? TimeInterval.infinity
            if leftTime != rightTime {
                return leftTime < rightTime
            }
            return left.kind.sortOrder < right.kind.sortOrder
        }
    }
}
