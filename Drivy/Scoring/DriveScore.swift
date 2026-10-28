import Foundation

/// Result of scoring one drive (S5). It is also the only drive payload that
/// leaves the device: raw GPS/motion samples are never uploaded (S10).
///
/// The one exception is `events`: S2 needs the position of each counted event to
/// draw it on the route, and those positions exist on this device only. The
/// upload payloads (`DriveRowPayload`) have no field for them, so they never
/// leave the phone (S10, S12).
struct DriveScore: Equatable {

    /// 0…100, rounded to the nearest point.
    let score: Int

    let distanceKm: Double

    let durationSeconds: TimeInterval

    let harshBrakes: Int

    let harshAccelerations: Int

    /// Counted even when connected mode waives the penalty (S13): the count is
    /// the fact, the penalty is the policy.
    let phoneUseEvents: Int

    let speedingEvents: Int

    let connectedMode: Bool

    /// S13: with the phone connected to the car, phone use is not penalized.
    var isPhoneUsePenaltyWaived: Bool {
        connectedMode
    }

    /// S2: every event the score counted, in time order, with its position when
    /// one could be derived from the route. Local only (S10, S12).
    let events: [DriveEvent]

    init(
        score: Int,
        distanceKm: Double,
        durationSeconds: TimeInterval,
        harshBrakes: Int,
        harshAccelerations: Int,
        phoneUseEvents: Int,
        speedingEvents: Int,
        connectedMode: Bool,
        events: [DriveEvent] = []
    ) {
        self.score = score
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.harshBrakes = harshBrakes
        self.harshAccelerations = harshAccelerations
        self.phoneUseEvents = phoneUseEvents
        self.speedingEvents = speedingEvents
        self.connectedMode = connectedMode
        self.events = events
    }

    /// Reduced form used by the daily aggregate (S6) and by the league ranking.
    var aggregateInput: DriveScoreInput {
        DriveScoreInput(score: score, distanceKm: distanceKm)
    }
}

/// The two numbers the daily average (S6) needs from a drive.
struct DriveScoreInput: Equatable {

    let score: Int

    let distanceKm: Double
}
