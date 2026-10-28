import SwiftUI

/// The sign a quest wears (S3).
///
/// One mapping for every screen: Hoy, Camino and the quest board all read the
/// requirement through this, so a quest never appears as a triangle in one place
/// and a disc in another. The mapping is exhaustive over `QuestRequirement` on
/// purpose: a new requirement must choose its own sign instead of falling into a
/// default.
enum QuestSign {

    /// The road meaning of a quest rule.
    static func sign(for requirement: QuestRequirement) -> RoadSign.Kind {
        switch requirement {
        case .driveWithoutPhoneUse:
            // "Cero móvil": the phone is what must not happen, so it is drawn as
            // the prohibition it is.
            return .prohibition(systemName: "iphone")
        case .driveWithoutHarshBrakes, .driveWithoutHarshAccelerations, .driveWithoutEvents:
            // Something to watch for on the next drive, not a ban.
            return .warning(systemName: "exclamationmark")
        case .driveWithoutSpeeding:
            return .speedLimit(RoadSign.genericSpeedLimit)
        case .lesson:
            return .info(systemName: "book.closed")
        case .cleanDrive:
            // A score floor: the good outcome, drawn as a positive information
            // sign rather than a warning.
            return .info(systemName: "checkmark")
        case .connectedDrive:
            return .info(systemName: "iphone.radiowaves.left.and.right")
        }
    }

    /// The sign of a quest of the catalog.
    static func sign(for quest: DailyQuest) -> RoadSign.Kind {
        sign(for: quest.requirement)
    }
}
