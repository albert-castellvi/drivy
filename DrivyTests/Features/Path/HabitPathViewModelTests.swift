import XCTest
@testable import Drivy

/// State of the Camino tab (S3, S4): the path read through the shared progress
/// layer, the levels it records, and the errors it survives.
@MainActor
final class HabitPathViewModelTests: XCTestCase {

    /// 2026-03-10, a Tuesday, at 12:00 in Europe/Madrid.
    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }

    private var now: Date {
        madrid.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    private var todayKey: String {
        DriveDay.key(for: now, calendar: madrid)
    }

    private func makeSUT() -> (sut: HabitPathViewModel, progress: FakeProgressDataLoader) {
        let progress = FakeProgressDataLoader()
        progress.now = { self.now }
        let sut = HabitPathViewModel(
            progressLoader: progress,
            calendar: madrid,
            now: { self.now }
        )
        return (sut, progress)
    }

    private func drive(
        id: String = "row-1",
        distanceKm: Double = 5,
        harshBrakes: Int = 0
    ) -> DriveHistoryRow {
        DriveHistoryRow(
            id: id,
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(-3000),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: 90,
            harshBrakes: harshBrakes,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
    }

    private func threeSmoothDrives() -> [DriveHistoryRow] {
        [
            drive(id: "row-1"),
            drive(id: "row-2"),
            drive(id: "row-3")
        ]
    }

    func testLoadPublishesThePathFromEveryDrive() async {
        let (sut, progress) = makeSUT()
        progress.driveRows = threeSmoothDrives()

        await sut.load()

        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.snapshot.units.first?.qualifyingDrives, 3)
        XCTAssertEqual(sut.snapshot.units.first?.completedLevels, 1)
        // S3: the first unit counts every drive, so the read starts at the shared
        // floor instead of a lookback window.
        XCTAssertEqual(progress.drivesSinceCalls, [HabitPathEngine.allDrivesSince])
    }

    /// S3/S4: the level the engine reached is stored through the shared layer, so
    /// the server pays its 50 XP and stamps the `completedAt` that opens the next
    /// unit.
    func testANewLevelIsRecordedThroughTheSharedLayer() async {
        let (sut, progress) = makeSUT()
        progress.driveRows = threeSmoothDrives()

        await sut.load()

        XCTAssertEqual(progress.levels.count, 1)
        XCTAssertEqual(progress.levels.first?.unit, HabitUnit.smoothBraking.rawValue)
        XCTAssertEqual(progress.levels.first?.level, 1)
        XCTAssertEqual(progress.levels.first?.completedAt, now)
    }

    func testEveryLevelReachedAtOnceIsRecordedLowestFirst() async {
        let (sut, progress) = makeSUT()
        progress.driveRows = (0..<15).map { drive(id: "row-\($0)") }

        await sut.load()

        XCTAssertEqual(progress.levels.map(\.level), [1, 2, 3])
        XCTAssertEqual(Set(progress.levels.map(\.unit)), [HabitUnit.smoothBraking.rawValue])
    }

    func testASecondLoadDoesNotRecordTheSameLevelTwice() async {
        let (sut, progress) = makeSUT()
        progress.driveRows = threeSmoothDrives()

        await sut.load()
        await sut.load()

        XCTAssertEqual(progress.levels.count, 1)
        XCTAssertTrue(sut.snapshot.pendingLevels.isEmpty)
        XCTAssertEqual(sut.snapshot.units.first?.completedLevels, 1)
    }

    func testALevelAlreadyOnTheServerIsNotRecordedAgain() async {
        let (sut, progress) = makeSUT()
        progress.levels = [
            HabitLevelRecord(unit: HabitUnit.smoothBraking.rawValue, level: 1, completedAt: now)
        ]
        progress.driveRows = threeSmoothDrives()

        await sut.load()

        XCTAssertEqual(progress.levels.count, 1)
        XCTAssertTrue(sut.snapshot.pendingLevels.isEmpty)
    }

    func testTodaysLessonIsReportedOnTheEntryCard() async {
        let (sut, progress) = makeSUT()
        progress.lessons[todayKey] = (correct: 4, total: 5)

        await sut.load()

        XCTAssertTrue(sut.snapshot.hasLessonToday)
    }

    func testALessonOnAnotherDayDoesNotCount() async {
        let (sut, progress) = makeSUT()
        progress.lessons["2026-03-09"] = (correct: 4, total: 5)

        await sut.load()

        XCTAssertFalse(sut.snapshot.hasLessonToday)
    }

    func testAnEmptyAccountShowsTheWholeTrail() async {
        let (sut, _) = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.snapshot.units.count, HabitUnit.allCases.count)
        XCTAssertEqual(sut.snapshot.completedLevels, 0)
        XCTAssertTrue(sut.snapshot.pendingLevels.isEmpty)
        XCTAssertNil(sut.errorMessage)
    }

    func testAFailedRefreshKeepsThePathOnScreen() async {
        let (sut, progress) = makeSUT()
        progress.driveRows = threeSmoothDrives()
        await sut.load()
        let loaded = sut.snapshot

        progress.failure = FakeProgressDataLoader.FakeError.network
        await sut.load()

        XCTAssertEqual(sut.snapshot, loaded)
        XCTAssertEqual(sut.errorMessage, HabitPathViewModel.loadFailureMessage)
        XCTAssertFalse(sut.isLoading)
    }
}
