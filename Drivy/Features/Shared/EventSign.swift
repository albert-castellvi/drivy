import SwiftUI

/// The sign a drive event wears (S3).
///
/// The same vocabulary as the quests, in one place: a harsh brake or a harsh
/// acceleration is a warning triangle, the phone is a prohibition, and speeding is
/// a speed-limit disc. Debrief, the map markers and the history rows all read
/// through this so one event never changes shape between screens.
enum EventSign {

    /// The road meaning of an event kind.
    static func sign(for kind: DriveEventKind) -> RoadSign.Kind {
        switch kind {
        case .harshBrake, .harshAcceleration:
            return .warning(systemName: "exclamationmark")
        case .phoneUse:
            return .prohibition(systemName: "iphone")
        case .speeding:
            return .speedLimit(RoadSign.genericSpeedLimit)
        }
    }
}
