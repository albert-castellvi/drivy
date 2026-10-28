import XCTest
@testable import Drivy

/// Habit path (S3): levels of 3 / 7 / 15 qualifying drives, counted since the unit
/// opened, with the 2 km floor shared with the quests. The reference day is
/// 2026-03-10 at 12:00 in Europe/Madrid so a drive "before" and "after" an unlock
/// are unambiguous.
final class HabitPathEngineTests: XCTestCase {

    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }

    private func date(day: Int, hour: Int = 12) -> Date {
        madrid.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    private var now: Date {
        date(day: 10)
    }

    private func drive(
        id: String = "row-1",
        startedAt: Date? = nil,
        distanceKm: Double = 5,
        harshBrakes: Int = 0,
        harshAccelerations: Int = 0,
        phoneUseEvents: Int = 0,
        speedingEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveHistoryRow {
        let start = startedAt ?? date(day: 9)
        return DriveHistoryRow(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: 90,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: connectedMode
        )
    }

    /// `count` drives that qualify for the first unit (no harsh brakes).
    private func smoothDrives(_ count: Int, distanceKm: Double = 5) -> [DriveHistoryRow] {
        (0..<count).map { index in
            drive(id: "row-\(index)", distanceKm: distanceKm)
        }
    }

    private func levels(_ unit: HabitUnit, _ recorded: [Int], completedAt: Date? = nil) -> [HabitLevelRecord] {
        recorded.map { level in
            HabitLevelRecord(unit: unit.rawValue, level: level, completedAt: completedAt ?? date(day: 1))
        }
    }

    private func path(
        drives: [DriveHistoryRow] = [],
        levels: [HabitLevelRecord] = [],
        hasLessonToday: Bool = false
    ) -> HabitPathSnapshot {
        HabitPathEngine.path(
            drives: drives,
            levels: levels,
            hasLessonToday: hasLessonToday,
            now: now
        )
    }

    // MARK: - The first unit

    func testTheFirstUnitCountsEveryDriveFromTheStart() {
        let sut = path(drives: [
            drive(id: "row-1", startedAt: date(day: 1)),
            drive(id: "row-2", startedAt: date(day: 5)),
            drive(id: "row-3", startedAt: date(day: 6)),
            drive(id: "row-4", startedAt: date(day: 9))
        ])

        XCTAssertEqual(sut.units.count, HabitUnit.allCases.count)
        XCTAssertTrue(sut.units[0].isUnlocked)
        XCTAssertEqual(sut.units[0].qualifyingDrives, 4)
        XCTAssertEqual(sut.units[0].completedLevels, 1)
        XCTAssertEqual(sut.pendingLevels, [PendingHabitLevel(unit: .smoothBraking, level: 1)])
    }

    func testEveryUnitAfterTheFirstStartsLocked() {
        let sut = path(drives: smoothDrives(3))

        for progress in sut.units.dropFirst() {
            XCTAssertFalse(progress.isUnlocked, "\(progress.unit.rawValue) should be locked")
            XCTAssertEqual(progress.qualifyingDrives, 0)
            XCTAssertEqual(progress.completedLevels, 0)
            XCTAssertEqual(progress.progressFraction, 0)
            XCTAssertNil(progress.progressText)
            XCTAssertNil(progress.nextLevelRequirement)
        }
    }

    func testALockedUnitNamesTheUnitThatOpensIt() {
        let sut = path()

        XCTAssertEqual(sut.units[0].statusText, "Nivel 1 de 3")
        XCTAssertEqual(sut.units[0].progressText, "0 de 3 trayectos")
        XCTAssertEqual(sut.units[1].statusText, "Se abre al terminar «Frenada suave»")
    }

    // MARK: - The 2 km floor

    func testAShorterDriveIsNotJudged() {
        let sut = path(drives: smoothDrives(5, distanceKm: 1.9))

        XCTAssertEqual(sut.units[0].qualifyingDrives, 0)
        XCTAssertEqual(sut.units[0].completedLevels, 0)
        XCTAssertTrue(sut.pendingLevels.isEmpty)
    }

    /// S3: "Cuentan trayectos de ≥ 2 km", so exactly 2 km counts.
    func testTheDistanceFloorIsInclusive() {
        let sut = path(drives: smoothDrives(3, distanceKm: HabitPathEngine.qualifyingDistanceKm))

        XCTAssertEqual(sut.units[0].qualifyingDrives, 3)
        XCTAssertEqual(sut.units[0].completedLevels, 1)
    }

    // MARK: - The levels

    func testLevelsNeedThreeSevenAndFifteenDrives() {
        XCTAssertEqual(HabitPathEngine.levelRequirements, [3, 7, 15])
        XCTAssertEqual(path(drives: smoothDrives(2)).units[0].completedLevels, 0)
        XCTAssertEqual(path(drives: smoothDrives(3)).units[0].completedLevels, 1)
        XCTAssertEqual(path(drives: smoothDrives(7)).units[0].completedLevels, 2)
        XCTAssertEqual(path(drives: smoothDrives(15)).units[0].completedLevels, 3)
    }

    func testEachLevelIsQueuedOnlyOnceInOrder() {
        let sut = path(drives: smoothDrives(15))

        XCTAssertEqual(
            sut.pendingLevels,
            [
                PendingHabitLevel(unit: .smoothBraking, level: 1),
                PendingHabitLevel(unit: .smoothBraking, level: 2),
                PendingHabitLevel(unit: .smoothBraking, level: 3)
            ]
        )
        XCTAssertEqual(sut.units[0].completedLevels, 3)
    }

    func testRecordedLevelsAreNotQueuedAgain() {
        let sut = path(drives: smoothDrives(7), levels: levels(.smoothBraking, [1, 2]))

        XCTAssertTrue(sut.pendingLevels.isEmpty)
        XCTAssertEqual(sut.units[0].completedLevels, 2)
        XCTAssertEqual(sut.units[0].nextLevel, 3)
        XCTAssertEqual(sut.units[0].nextLevelRequirement, 15)
        XCTAssertEqual(sut.units[0].progressText, "7 de 15 trayectos")
        XCTAssertEqual(sut.units[0].statusText, "Nivel 3 de 3")
        XCTAssertEqual(sut.units[0].progressFraction, 7.0 / 15.0, accuracy: 0.0001)
    }

    func testACompletedUnitHasNoNextLevel() {
        let sut = path(levels: levels(.smoothBraking, [1, 2, 3]))

        XCTAssertTrue(sut.units[0].isCompleted)
        XCTAssertEqual(sut.units[0].statusText, "Completado")
        XCTAssertNil(sut.units[0].progressText)
        XCTAssertEqual(sut.units[0].progressFraction, 1)
    }

    /// The counting is cumulative since the unit opened, so a level never moves the
    /// start line: 15 drives are levels 1, 2 and 3, not 25.
    func testTheCountIsCappedAtTheLastRequirement() {
        let sut = path(drives: smoothDrives(40))

        XCTAssertEqual(sut.units[0].qualifyingDrives, 15)
    }

    // MARK: - Unlocking the next unit

    func testTheNextUnitCountsOnlyDrivesAfterItOpened() {
        let unlock = date(day: 5, hour: 9)
        let sut = path(
            drives: [
                drive(id: "row-1", startedAt: date(day: 1), harshBrakes: 3),
                drive(id: "row-2", startedAt: date(day: 6), harshBrakes: 3),
                drive(id: "row-3", startedAt: date(day: 7), harshBrakes: 3)
            ],
            levels: levels(.smoothBraking, [1, 2, 3], completedAt: unlock)
        )

        XCTAssertTrue(sut.units[1].isUnlocked)
        XCTAssertEqual(sut.units[1].qualifyingDrives, 2)
        XCTAssertEqual(sut.units[1].completedLevels, 0)
        XCTAssertEqual(sut.units[1].progressText, "2 de 3 trayectos")
        XCTAssertTrue(sut.pendingLevels.isEmpty)
    }

    /// The path never goes backwards: a level the server already recorded stays
    /// completed even when the drives of that period are no longer readable.
    func testRecordedLevelsSurviveWithoutTheirDrives() {
        let sut = path(levels: levels(.smoothBraking, [1, 2, 3]))

        XCTAssertEqual(sut.units[0].qualifyingDrives, 0)
        XCTAssertEqual(sut.units[0].completedLevels, 3)
        XCTAssertTrue(sut.pendingLevels.isEmpty)
        XCTAssertTrue(sut.units[1].isUnlocked)
    }

    /// S3: unit N+1 opens at the `completedAt` of the third level, so a level that
    /// is reached but not recorded yet cannot open it.
    func testAQueuedThirdLevelDoesNotOpenTheNextUnit() {
        let sut = path(drives: smoothDrives(15))

        XCTAssertEqual(sut.units[0].completedLevels, 3)
        XCTAssertEqual(sut.pendingLevels.count, 3)
        XCTAssertFalse(sut.units[1].isUnlocked)
    }

    // MARK: - Reference date

    func testADriveThatStartsLaterDoesNotCount() {
        let sut = path(
            drives: smoothDrives(3) + [
                drive(id: "row-future", startedAt: now.addingTimeInterval(60 * 60 * 24))
            ]
        )

        XCTAssertEqual(sut.units[0].qualifyingDrives, 3)
    }

    // MARK: - Whole path

    func testTheWholePathAddsUpItsLevelsAndTheirXP() {
        let allLevels = HabitUnit.allCases.flatMap { unit in
            levels(unit, [1, 2, 3])
        }
        let sut = path(levels: allLevels)

        XCTAssertEqual(sut.completedLevels, 15)
        XCTAssertEqual(sut.totalLevels, 15)
        XCTAssertEqual(sut.xpFromLevels, 15 * HabitPathEngine.xpPerLevel)
        XCTAssertEqual(HabitPathEngine.xpPerLevel, 50)
        XCTAssertNil(sut.currentUnit)
        XCTAssertTrue(sut.units.allSatisfy { $0.isCompleted })
    }

    func testTheCurrentUnitIsTheFirstOneStillInProgress() {
        let sut = path(
            levels: levels(.smoothBraking, [1, 2, 3]) + levels(.smoothAcceleration, [1])
        )

        XCTAssertEqual(sut.currentUnit?.unit, .smoothAcceleration)
    }

    func testAnEmptyPathShowsTheWholeTrail() {
        let sut = path()

        XCTAssertEqual(sut.units.count, HabitUnit.allCases.count)
        XCTAssertEqual(sut.completedLevels, 0)
        XCTAssertEqual(sut.xpFromLevels, 0)
        XCTAssertEqual(sut.currentUnit?.unit, .smoothBraking)
        XCTAssertTrue(sut.pendingLevels.isEmpty)
        XCTAssertFalse(sut.hasLessonToday)
    }

    /// S2: the entry card of the tab knows whether today's lesson is done.
    func testTheLessonStateIsCarriedThrough() {
        XCTAssertTrue(path(hasLessonToday: true).hasLessonToday)
        XCTAssertFalse(HabitPathSnapshot.empty.hasLessonToday)
    }
}
