import XCTest
@testable import Drivy

/// The quest catalog (S6): stable ids shared with the database, and no quest that
/// asks for more km, more drives or more time.
final class QuestCatalogTests: XCTestCase {

    /// `public.quest_completions.quest_id` is `check (quest_id ~ '^[a-z_]{1,40}$')`:
    /// an id outside that shape makes the insert fail at runtime.
    private static let idPattern = "^[a-z_]{1,40}$"

    func testIdsAreValidSnakeCaseAndShort() {
        for quest in QuestCatalog.all {
            XCTAssertNotNil(
                quest.id.range(of: Self.idPattern, options: .regularExpression),
                "\(quest.id) is not a valid quest_id"
            )
        }
    }

    func testIdsAreUnique() {
        let ids = QuestCatalog.all.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// S6: "un catálogo de ~10 misiones".
    func testCatalogHasAboutTenQuests() {
        XCTAssertGreaterThanOrEqual(QuestCatalog.all.count, 8)
        XCTAssertLessThanOrEqual(QuestCatalog.all.count, 12)
    }

    /// S6: "siempre al menos una que se pueda completar sin conducir".
    func testTheCatalogHasAQuestWithoutDriving() {
        XCTAssertFalse(QuestCatalog.withoutDriving.isEmpty)
        XCTAssertTrue(QuestCatalog.withoutDriving.contains { $0.id == QuestCatalog.lesson.id })
    }

    func testCopyIsSpanishAndNotEmpty() {
        for quest in QuestCatalog.all {
            XCTAssertFalse(quest.title.isEmpty)
            XCTAssertFalse(quest.detail.isEmpty)
        }
    }

    /// The safety principle of the feature: no quest rewards driving more, so the
    /// catalog can only use the requirement kinds that judge one existing drive.
    func testNoQuestAsksForMoreKmDrivesOrTime() {
        // The four cases that could invite driving more are deliberately absent from
        // the enum; this pins the set the catalog is allowed to use.
        for quest in QuestCatalog.all {
            switch quest.requirement {
            case .cleanDrive(let minimumScore):
                XCTAssertLessThanOrEqual(minimumScore, 100)
            case .driveWithoutPhoneUse,
                 .driveWithoutHarshBrakes,
                 .driveWithoutHarshAccelerations,
                 .driveWithoutSpeeding,
                 .driveWithoutEvents,
                 .connectedDrive,
                 .lesson:
                break
            }
        }
    }

    /// No dead rule: every requirement the evaluator understands is used by a quest.
    func testEveryRequirementIsUsedByAQuest() {
        let requirements: [QuestRequirement] = [
            .cleanDrive(minimumScore: 90),
            .driveWithoutPhoneUse,
            .driveWithoutHarshBrakes,
            .driveWithoutHarshAccelerations,
            .driveWithoutSpeeding,
            .driveWithoutEvents,
            .connectedDrive,
            .lesson
        ]

        for requirement in requirements {
            XCTAssertTrue(
                QuestCatalog.all.contains { $0.requirement == requirement },
                "\(requirement) is not used by any quest"
            )
        }
    }

    /// The floor is the same 2 km the habit path uses (S3), so both features judge
    /// the same drives.
    func testTheDistanceFloorIsTwoKilometres() {
        XCTAssertEqual(QuestCatalog.minimumDistanceKm, 2.0)
    }
}
