import Foundation

/// Where an event of one drive happened, in plain degrees.
///
/// A dedicated value type instead of `CLLocationCoordinate2D` so the scoring layer
/// keeps importing nothing but Foundation, exactly like `LocationSample` (see
/// `ScoringEngine`). The coordinates are local only: they feed the post-drive map
/// of S2 and never reach an upload payload (S10, S12).
struct DriveCoordinate: Equatable {

    let latitude: Double

    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The events the scoring engine counts (S5).
enum DriveEventKind: String, CaseIterable, Equatable {

    case harshBrake
    case harshAcceleration
    case speeding
    case phoneUse

    /// Points one event of this kind costs per kilometre (S5).
    ///
    /// The same coefficients `ScoringEngine` charges, read from `ScoringRules` so
    /// the post-drive summary (S2) ranks the components of a drive with the exact
    /// numbers that produced its score instead of restating them.
    var penaltyPerKm: Double {
        switch self {
        case .harshBrake:
            return ScoringRules.harshBrakingPenaltyPerKm
        case .harshAcceleration:
            return ScoringRules.harshAccelerationPenaltyPerKm
        case .speeding:
            return ScoringRules.speedingPenaltyPerKm
        case .phoneUse:
            return ScoringRules.phoneUsePenaltyPerKm
        }
    }

    /// Fixed order used for lists and for the tie of two events counted on the
    /// same fix, so nothing the user sees depends on the order of the detection
    /// passes.
    var sortOrder: Int {
        switch self {
        case .harshBrake:
            return 0
        case .harshAcceleration:
            return 1
        case .speeding:
            return 2
        case .phoneUse:
            return 3
        }
    }
}

/// One event the score counted, with where it happened when that can be derived
/// (S2: "el motor de scoring pasa a devolver la posición de cada evento").
///
/// Local only: it rides on `DriveRecord` so the post-drive summary can draw it,
/// and it is deliberately absent from the upload payloads (S10, S12). Events only
/// ever cost points, so nothing here can reward driving further or more often.
struct DriveEvent: Equatable {

    let kind: DriveEventKind

    /// Seconds on the same monotonic scale as `LocationSample.timestamp`, i.e.
    /// measured from the first fix of the drive. `nil` when the event has no
    /// position in time: phone use is counted as a drive-level fact (S5).
    let timestamp: TimeInterval?

    /// Coordinate of the fix nearest in time, or `nil` when the drive has no route
    /// available on this device (a row read back from the server, a re-score).
    let coordinate: DriveCoordinate?

    init(
        kind: DriveEventKind,
        timestamp: TimeInterval? = nil,
        coordinate: DriveCoordinate? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.coordinate = coordinate
    }
}
