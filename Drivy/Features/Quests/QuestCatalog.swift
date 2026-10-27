import Foundation

/// What a quest asks for, as a rule over today's data (S6).
///
/// Every case is about the **quality** of a drive that already happened, never
/// about more km, more drives or more time: the safety principle of the whole
/// feature forbids rewarding driving more, so no quest can ask for a longer or an
/// extra drive. Each rule is satisfied by a single qualifying drive.
enum QuestRequirement: Equatable {

    /// A drive of at least the shared distance floor with a score this high.
    case cleanDrive(minimumScore: Int)

    /// A drive with no phone use events.
    case driveWithoutPhoneUse

    /// A drive with no harsh brakes.
    case driveWithoutHarshBrakes

    /// A drive with no harsh accelerations.
    case driveWithoutHarshAccelerations

    /// A drive with no speeding events.
    case driveWithoutSpeeding

    /// A drive with no event of any kind.
    case driveWithoutEvents

    /// A drive recorded in connected mode (S13).
    case connectedDrive

    /// Today's theory lesson completed.
    case lesson

    /// `true` for the quests that need a drive. The daily board always keeps at
    /// least one quest on the other side (S6).
    var needsDriving: Bool {
        self != .lesson
    }
}

/// One quest of the daily board (S6).
struct DailyQuest: Equatable, Identifiable {

    /// Stable snake_case key, shared with `public.quest_completions.quest_id`
    /// (`^[a-z_]{1,40}$`). Renaming one orphans every row already recorded, so the
    /// catalog only ever grows.
    let id: String

    /// Short title of the row.
    let title: String

    /// What the quest asks for, in one line.
    let detail: String

    let requirement: QuestRequirement
}

/// The quest catalog (S6): about ten quests, all of them about how the user
/// drove, none of them about how much.
enum QuestCatalog {

    /// Distance a drive needs to count for any drive quest. The same 2 km floor
    /// as the habit path (S3), so a quest and the habit path never disagree about
    /// which drives count.
    static let minimumDistanceKm = 2.0

    /// The quest that never needs a car (S6: "siempre al menos una que se pueda
    /// completar sin conducir").
    static let lesson = DailyQuest(
        id: "lesson",
        title: "Lección de hoy",
        detail: "Completa la lección de teoría de hoy.",
        requirement: .lesson
    )

    /// Every quest, in a stable order. The daily board picks from here.
    static let all: [DailyQuest] = [
        lesson,
        DailyQuest(
            id: "clean_drive",
            title: "Trayecto limpio",
            detail: "Un trayecto de 2 km o más con nota 90 o superior.",
            requirement: .cleanDrive(minimumScore: 90)
        ),
        DailyQuest(
            id: "perfect_drive",
            title: "Trayecto impecable",
            detail: "Un trayecto de 2 km o más con nota 95 o superior.",
            requirement: .cleanDrive(minimumScore: 95)
        ),
        DailyQuest(
            id: "careful_drive",
            title: "Conducción atenta",
            detail: "Un trayecto de 2 km o más con nota 75 o superior.",
            requirement: .cleanDrive(minimumScore: 75)
        ),
        DailyQuest(
            id: "no_events_drive",
            title: "Trayecto sin sustos",
            detail: "Un trayecto de 2 km o más sin ningún evento.",
            requirement: .driveWithoutEvents
        ),
        DailyQuest(
            id: "no_phone_drive",
            title: "Cero móvil",
            detail: "Un trayecto de 2 km o más sin tocar el móvil.",
            requirement: .driveWithoutPhoneUse
        ),
        DailyQuest(
            id: "smooth_brakes",
            title: "Frenada suave",
            detail: "Un trayecto de 2 km o más sin frenadas bruscas.",
            requirement: .driveWithoutHarshBrakes
        ),
        DailyQuest(
            id: "smooth_start",
            title: "Arranque suave",
            detail: "Un trayecto de 2 km o más sin aceleraciones bruscas.",
            requirement: .driveWithoutHarshAccelerations
        ),
        DailyQuest(
            id: "legal_speed",
            title: "Velocidad legal",
            detail: "Un trayecto de 2 km o más sin excesos de velocidad.",
            requirement: .driveWithoutSpeeding
        ),
        DailyQuest(
            id: "connected_drive",
            title: "Conducción conectada",
            detail: "Un trayecto de 2 km o más en modo conectado.",
            requirement: .connectedDrive
        )
    ]

    /// Quests that need no driving at all.
    static var withoutDriving: [DailyQuest] {
        all.filter { !$0.requirement.needsDriving }
    }

    /// Quests that need one drive of at least the distance floor.
    static var withDriving: [DailyQuest] {
        all.filter { $0.requirement.needsDriving }
    }
}
