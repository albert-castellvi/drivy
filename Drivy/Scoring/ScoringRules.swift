import Foundation

/// Scoring v1 coefficients (S5, S13).
///
/// Thresholds quote the spec verbatim; every weight is expressed in points per
/// event **per kilometre**, so a 40 km motorway drive with one harsh brake is
/// not punished like a 2 km city hop with the same brake.
///
/// At-the-threshold values are deliberately *not* violations (the spec says
/// "> 3.5", "> 3.0", "+10"): the comparisons in `ScoringEngine` are strict.
enum ScoringRules {

    /// Bumped whenever a threshold or a weight changes. It is stored inside the
    /// drive summary, so old rows stay comparable and can be re-scored (S10).
    static let version = 1

    // MARK: - Thresholds (S5)

    /// "frenadas bruscas (desaceleración > 3.5 m/s²)".
    static let harshBrakingThreshold = 3.5

    /// "aceleraciones bruscas (> 3.0 m/s²)".
    static let harshAccelerationThreshold = 3.0

    /// "exceso de velocidad respecto al límite (umbral +10 km/h)".
    static let speedingToleranceKmh = 10.0

    // MARK: - Event de-duplication

    /// A sensor at 50 Hz reports the same hard brake dozens of times. An event
    /// stays open until the signal falls back to this fraction of its
    /// threshold, so one brake is one event and not fifty.
    static let eventReleaseRatio = 0.7

    /// Speeding counterpart of `eventReleaseRatio`, in km/h: the speed has to
    /// drop this far below the offending threshold before a second event can be
    /// counted.
    static let speedingReleaseKmh = 3.0

    /// Signal level that closes a braking event (−3.5 × 0.7 = −2.45 m/s²).
    static let harshBrakingReleaseThreshold = harshBrakingThreshold * eventReleaseRatio

    /// Signal level that closes an acceleration event (3.0 × 0.7 = 2.1 m/s²).
    static let harshAccelerationReleaseThreshold = harshAccelerationThreshold * eventReleaseRatio

    // MARK: - Weights (points per event per km)

    static let harshBrakingPenaltyPerKm = 12.0
    static let harshAccelerationPenaltyPerKm = 8.0
    static let phoneUsePenaltyPerKm = 25.0
    static let speedingPenaltyPerKm = 10.0

    // MARK: - Connected mode (S13)

    /// "Conducción conectada → bonus en el score".
    static let connectedModeBonus = 5.0

    // MARK: - Guards

    /// Penalties are per km, so a drive shorter than this would divide by a
    /// number close to zero and go straight to 0. Short drives are scored as if
    /// they were this long.
    static let minimumDistanceKm = 0.1
}
