import Foundation

/// Result of scoring one drive (S5). It is also the only drive payload that
/// leaves the device: raw GPS/motion samples are never uploaded (S10).
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
