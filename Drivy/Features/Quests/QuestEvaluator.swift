import Foundation

/// Today's data a quest rule is evaluated against (S6).
struct QuestDayContext: Equatable {

    /// Drives of the local day, as `public.drives` returns them.
    let drives: [DriveHistoryRow]

    /// True when today's theory lesson is already recorded (it is what makes the
    /// `lesson` quest complete, S2).
    let isLessonDone: Bool

    static let empty = QuestDayContext(drives: [], isLessonDone: false)
}

/// Completion rule of a quest (S6).
///
/// Pure: no clock, no network, no storage. The caller hands it today's drives and
/// whether the lesson is done, because that is exactly what the day holds, and the
/// answer is therefore the same on every device and every refresh.
enum QuestEvaluator {

    static func isSatisfied(_ quest: DailyQuest, in context: QuestDayContext) -> Bool {
        switch quest.requirement {
        case .cleanDrive(let minimumScore):
            return context.drives.contains { qualifies($0) && $0.score >= minimumScore }
        case .driveWithoutPhoneUse:
            return context.drives.contains { qualifies($0) && $0.phoneUseEvents == 0 }
        case .driveWithoutHarshBrakes:
            return context.drives.contains { qualifies($0) && $0.harshBrakes == 0 }
        case .driveWithoutHarshAccelerations:
            return context.drives.contains { qualifies($0) && $0.harshAccelerations == 0 }
        case .driveWithoutSpeeding:
            return context.drives.contains { qualifies($0) && $0.speedingEvents == 0 }
        case .driveWithoutEvents:
            return context.drives.contains { drive in
                qualifies(drive)
                    && drive.harshBrakes == 0
                    && drive.harshAccelerations == 0
                    && drive.phoneUseEvents == 0
                    && drive.speedingEvents == 0
            }
        case .connectedDrive:
            return context.drives.contains { qualifies($0) && $0.connectedMode }
        case .lesson:
            return context.isLessonDone
        }
    }

    /// A drive counts for a quest only from the shared distance floor: a quest is
    /// about how the drive went, so a shorter one is simply not judged.
    static func qualifies(_ drive: DriveHistoryRow) -> Bool {
        drive.distanceKm >= QuestCatalog.minimumDistanceKm
    }
}

/// One of the three quests of the day, as the Hoy screen shows it (S6).
struct DailyQuestProgress: Equatable, Identifiable {

    let quest: DailyQuest

    /// True when today's data already satisfies the rule.
    let isCompleted: Bool

    var id: String { quest.id }
}
