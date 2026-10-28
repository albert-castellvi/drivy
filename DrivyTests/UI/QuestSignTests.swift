import XCTest
@testable import Drivy

/// S3: every quest wears one sign, and it wears it on every screen. Hoy, Camino
/// and the quest board all read the requirement through `QuestSign`, so the mapping
/// is pinned per quest of the catalog and per case of `QuestRequirement`: a new
/// requirement must choose its own sign instead of inheriting a default.
final class QuestSignTests: XCTestCase {

    /// The sign S3 fixes for each quest, by the stable snake_case id the catalog
    /// shares with `public.quest_completions.quest_id`.
    private static var expected: [(id: String, kind: RoadSign.Kind)] {
        [
            ("lesson", .info(systemName: "book.closed")),
            ("clean_drive", .info(systemName: "checkmark")),
            ("perfect_drive", .info(systemName: "checkmark")),
            ("careful_drive", .info(systemName: "checkmark")),
            ("no_events_drive", .warning(systemName: "exclamationmark")),
            ("no_phone_drive", .prohibition(systemName: "iphone")),
            ("smooth_brakes", .warning(systemName: "exclamationmark")),
            ("smooth_start", .warning(systemName: "exclamationmark")),
            ("legal_speed", .speedLimit(50)),
            ("connected_drive", .info(systemName: "iphone.radiowaves.left.and.right"))
        ]
    }

    /// One representative of each of the eight cases of `QuestRequirement`, with
    /// the sign S3 fixes for it. `QuestRequirement` is not `CaseIterable`, so this
    /// table — and its count — is what proves no case is left unmapped.
    private static var requirements: [(requirement: QuestRequirement, kind: RoadSign.Kind)] {
        [
            (.lesson, .info(systemName: "book.closed")),
            (.cleanDrive(minimumScore: 90), .info(systemName: "checkmark")),
            (.driveWithoutEvents, .warning(systemName: "exclamationmark")),
            (.driveWithoutPhoneUse, .prohibition(systemName: "iphone")),
            (.driveWithoutHarshBrakes, .warning(systemName: "exclamationmark")),
            (.driveWithoutHarshAccelerations, .warning(systemName: "exclamationmark")),
            (.driveWithoutSpeeding, .speedLimit(50)),
            (.connectedDrive, .info(systemName: "iphone.radiowaves.left.and.right"))
        ]
    }

    // MARK: - The catalog

    func testEveryCatalogQuestWearsTheSignOfItsRequirement() {
        for quest in QuestCatalog.all {
            guard let expectation = Self.expected.first(where: { $0.id == quest.id }) else {
                XCTFail("quest \"\(quest.id)\" (\(quest.title)) has no expected sign")
                continue
            }

            XCTAssertEqual(
                QuestSign.sign(for: quest),
                expectation.kind,
                "quest \"\(quest.id)\" (\(quest.title)) wears the wrong sign"
            )
        }
    }

    /// The other direction: an expectation of a quest that no longer exists would
    /// keep the test green while the mapping rotted.
    func testEveryExpectedQuestIdExistsInTheCatalog() {
        let catalogIds = QuestCatalog.all.map { $0.id }

        for expectation in Self.expected {
            XCTAssertTrue(
                catalogIds.contains(expectation.id),
                "expectation \"\(expectation.id)\" matches no quest of QuestCatalog.all"
            )
        }
    }

    // MARK: - Every requirement case

    func testEveryRequirementCaseHasASign() {
        XCTAssertEqual(
            Self.requirements.count,
            8,
            "QuestRequirement has eight cases: the expectation table must cover all of them"
        )

        for sample in Self.requirements {
            XCTAssertEqual(
                QuestSign.sign(for: sample.requirement),
                sample.kind,
                "requirement \(sample.requirement) wears the wrong sign"
            )
        }
    }

    /// No quest of the catalog may use a requirement that the S3 table does not
    /// cover. `cleanDrive` carries its floor as an associated value, so any score
    /// counts as covered by the one sample.
    func testEveryCatalogRequirementIsCoveredByTheExpectationTable() {
        for quest in QuestCatalog.all {
            let covered = Self.requirements.contains { $0.requirement == quest.requirement }

            XCTAssertTrue(
                covered || Self.isCleanDrive(quest.requirement),
                "quest \"\(quest.id)\" uses a requirement the S3 table does not cover"
            )
        }
    }

    // MARK: - The signs that carry a rule of their own

    /// "Cero móvil" is the one ban of the board: the phone is what must not happen.
    func testPhoneQuestIsAProhibitionDiscWithThePhone() {
        XCTAssertEqual(
            QuestSign.sign(for: .driveWithoutPhoneUse),
            .prohibition(systemName: "iphone")
        )
    }

    /// Speeding has a real sign of its own, the urban limit the lessons teach.
    func testSpeedingQuestIsASpeedLimitDisc() {
        XCTAssertEqual(QuestSign.sign(for: .driveWithoutSpeeding), .speedLimit(50))
        XCTAssertEqual(
            RoadSign.genericSpeedLimit,
            50,
            "the shared speed limit of the system is the 50 of the urban default (S3)"
        )
    }

    /// The lesson is the quest that needs no car, and it is information, not a
    /// warning: the board always keeps one of these.
    func testLessonQuestIsTheInformationSignOfTheLesson() {
        XCTAssertEqual(
            QuestSign.sign(for: QuestCatalog.lesson),
            .info(systemName: "book.closed")
        )
    }

    private static func isCleanDrive(_ requirement: QuestRequirement) -> Bool {
        if case .cleanDrive = requirement {
            return true
        }
        return false
    }
}
