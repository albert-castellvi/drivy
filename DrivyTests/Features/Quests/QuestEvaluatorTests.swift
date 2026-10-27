import XCTest
@testable import Drivy

/// Completion rules of the daily quests (S6), asserted as pure values.
final class QuestEvaluatorTests: XCTestCase {

    private func drive(
        score: Int = 90,
        distanceKm: Double = 5,
        harshBrakes: Int = 0,
        harshAccelerations: Int = 0,
        phoneUseEvents: Int = 0,
        speedingEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveHistoryRow {
        let start = Date(timeIntervalSince1970: 1_772_340_000)
        return DriveHistoryRow(
            id: "row-1",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: score,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: connectedMode
        )
    }

    private func isSatisfied(
        _ requirement: QuestRequirement,
        drives: [DriveHistoryRow],
        lessonDone: Bool = false
    ) -> Bool {
        let quest = DailyQuest(id: "test_quest", title: "", detail: "", requirement: requirement)
        return QuestEvaluator.isSatisfied(
            quest,
            in: QuestDayContext(drives: drives, isLessonDone: lessonDone)
        )
    }

    // MARK: - Clean drives (S1's threshold does not apply here: each quest has its own)

    func testCleanDriveNeedsItsScoreAndTheDistanceFloor() {
        XCTAssertTrue(isSatisfied(.cleanDrive(minimumScore: 90), drives: [drive(score: 90)]))
        XCTAssertFalse(isSatisfied(.cleanDrive(minimumScore: 90), drives: [drive(score: 89)]))
    }

    /// The shared floor: a shorter drive is not judged, so no quest can be
    /// completed by driving more.
    func testAShorterDriveDoesNotCountForAnyQuest() {
        let short = drive(distanceKm: QuestCatalog.minimumDistanceKm - 0.1)

        XCTAssertFalse(isSatisfied(.cleanDrive(minimumScore: 75), drives: [short]))
        XCTAssertFalse(isSatisfied(.driveWithoutPhoneUse, drives: [short]))
        XCTAssertFalse(isSatisfied(.driveWithoutHarshBrakes, drives: [short]))
        XCTAssertFalse(isSatisfied(.driveWithoutHarshAccelerations, drives: [short]))
        XCTAssertFalse(isSatisfied(.driveWithoutSpeeding, drives: [short]))
        XCTAssertFalse(isSatisfied(.driveWithoutEvents, drives: [short]))
        XCTAssertFalse(isSatisfied(.connectedDrive, drives: [short]))
    }

    func testExactlyTheDistanceFloorCounts() {
        let drive = drive(distanceKm: QuestCatalog.minimumDistanceKm)

        XCTAssertTrue(isSatisfied(.cleanDrive(minimumScore: 75), drives: [drive]))
    }

    // MARK: - Event-free drives

    func testNoPhoneQuestNeedsAZeroCount() {
        XCTAssertTrue(isSatisfied(.driveWithoutPhoneUse, drives: [drive(phoneUseEvents: 0)]))
        XCTAssertFalse(isSatisfied(.driveWithoutPhoneUse, drives: [drive(phoneUseEvents: 1)]))
    }

    func testSmoothBrakesQuestNeedsAZeroCount() {
        XCTAssertTrue(isSatisfied(.driveWithoutHarshBrakes, drives: [drive(harshBrakes: 0)]))
        XCTAssertFalse(isSatisfied(.driveWithoutHarshBrakes, drives: [drive(harshBrakes: 2)]))
    }

    func testSmoothStartQuestNeedsAZeroCount() {
        XCTAssertTrue(
            isSatisfied(.driveWithoutHarshAccelerations, drives: [drive(harshAccelerations: 0)])
        )
        XCTAssertFalse(
            isSatisfied(.driveWithoutHarshAccelerations, drives: [drive(harshAccelerations: 1)])
        )
    }

    func testLegalSpeedQuestNeedsAZeroCount() {
        XCTAssertTrue(isSatisfied(.driveWithoutSpeeding, drives: [drive(speedingEvents: 0)]))
        XCTAssertFalse(isSatisfied(.driveWithoutSpeeding, drives: [drive(speedingEvents: 3)]))
    }

    func testNoEventsQuestNeedsEveryCountAtZero() {
        XCTAssertTrue(isSatisfied(.driveWithoutEvents, drives: [drive()]))
        XCTAssertFalse(isSatisfied(.driveWithoutEvents, drives: [drive(harshBrakes: 1)]))
        XCTAssertFalse(isSatisfied(.driveWithoutEvents, drives: [drive(harshAccelerations: 1)]))
        XCTAssertFalse(isSatisfied(.driveWithoutEvents, drives: [drive(phoneUseEvents: 1)]))
        XCTAssertFalse(isSatisfied(.driveWithoutEvents, drives: [drive(speedingEvents: 1)]))
    }

    func testConnectedDriveNeedsTheConnectedMode() {
        XCTAssertTrue(isSatisfied(.connectedDrive, drives: [drive(connectedMode: true)]))
        XCTAssertFalse(isSatisfied(.connectedDrive, drives: [drive(connectedMode: false)]))
    }

    // MARK: - Lesson

    func testTheLessonQuestNeedsTheLessonOfTheDay() {
        XCTAssertTrue(isSatisfied(.lesson, drives: [], lessonDone: true))
        XCTAssertFalse(isSatisfied(.lesson, drives: [], lessonDone: false))
        // A drive is not a lesson: the quest that needs no car cannot be completed
        // by driving either.
        XCTAssertFalse(isSatisfied(.lesson, drives: [drive()], lessonDone: false))
    }

    // MARK: - One drive is enough

    /// S6: no quest asks for more driving, so one qualifying drive completes every
    /// driving quest of the catalog.
    func testOneQualifyingDriveSatisfiesEveryDrivingQuest() {
        let drives = [drive(score: 100, connectedMode: true)]

        for quest in QuestCatalog.withDriving {
            XCTAssertTrue(
                QuestEvaluator.isSatisfied(quest, in: QuestDayContext(drives: drives, isLessonDone: false)),
                "\(quest.id) should be satisfied by a single qualifying drive"
            )
        }
    }

    func testADirtyDriveSatisfiesNoDrivingQuest() {
        let drives = [
            drive(
                score: 40,
                harshBrakes: 3,
                harshAccelerations: 2,
                phoneUseEvents: 4,
                speedingEvents: 5,
                connectedMode: false
            )
        ]

        for quest in QuestCatalog.withDriving {
            XCTAssertFalse(
                QuestEvaluator.isSatisfied(quest, in: QuestDayContext(drives: drives, isLessonDone: false)),
                "\(quest.id) must not be satisfied by a bad drive"
            )
        }
    }
}
