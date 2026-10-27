import XCTest
@testable import Drivy

/// State of the Hoy tab (S1, S4, S6, S8), exercised with a fake Supabase boundary.
@MainActor
final class TodayViewModelTests: XCTestCase {

    private static let userID = "user-1"

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

    private func dayKey(_ day: Int) -> String {
        let date = madrid.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))
        return DriveDay.key(for: date ?? now, calendar: madrid)
    }

    private func makeSUT() -> (
        sut: TodayViewModel,
        today: FakeTodayDataLoader,
        progress: FakeProgressDataLoader
    ) {
        let today = FakeTodayDataLoader()
        let progress = FakeProgressDataLoader()
        progress.now = { self.now }
        let sut = TodayViewModel(
            dataLoader: today,
            progressLoader: progress,
            calendar: madrid,
            now: { self.now }
        )
        return (sut, today, progress)
    }

    private func drive(score: Int, distanceKm: Double) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "row-\(score)",
            startedAt: now,
            endedAt: now.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: score,
            harshBrakes: 1,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
    }

    private func dailyScore(day: String, score: Int) -> DailyScoreRecord {
        DailyScoreRecord(day: day, score: score, distanceKm: 12.34, drivesCount: 1)
    }

    func testLoadPublishesTheDayAndTheStreak() async {
        let (sut, today, _) = makeSUT()
        today.dailyScoresResult = .success([
            dailyScore(day: dayKey(10), score: 87),
            dailyScore(day: dayKey(9), score: 91)
        ])
        today.drivesResult = .success([drive(score: 87, distanceKm: 12.34)])

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.snapshot.score, 87)
        XCTAssertEqual(sut.snapshot.distanceKm, 12.34)
        XCTAssertEqual(sut.snapshot.drivesCount, 1)
        XCTAssertEqual(sut.snapshot.streak.days, 2)
        XCTAssertEqual(sut.snapshot.drives.count, 1)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadUsesTheSignedInUserID() async {
        let (sut, today, _) = makeSUT()

        await sut.load(userID: Self.userID)

        XCTAssertEqual(today.dailyScoresCalls.last?.userID, Self.userID)
        XCTAssertEqual(today.drivesCalls.last?.userID, Self.userID)
    }

    /// S1/S8: the plan in force decides the weekly freezes.
    func testLoadUsesThePlanFreezes() async {
        let (sut, _, _) = makeSUT()

        await sut.load(userID: Self.userID, plan: .premium)

        XCTAssertEqual(sut.snapshot.streak.freezesLeftThisWeek, FreemiumLimits.premiumWeeklyFreezes)
    }

    /// S6: the quests the day already satisfies are stored, once.
    func testCompletedQuestsAreRecordedOnce() async {
        let (sut, _, progress) = makeSUT()
        progress.lessons[dayKey(10)] = (correct: 4, total: 5)

        await sut.load(userID: Self.userID)

        XCTAssertEqual(progress.quests[dayKey(10)] ?? [], Set([QuestCatalog.lesson.id]))

        await sut.load(userID: Self.userID)

        XCTAssertEqual(progress.quests[dayKey(10)] ?? [], Set([QuestCatalog.lesson.id]))
    }

    func testNothingIsRecordedWhenTheDayHasNoCompletedQuest() async {
        let (sut, _, progress) = makeSUT()

        await sut.load(userID: Self.userID)

        XCTAssertTrue(progress.quests.isEmpty)
    }

    /// S8: the repair is written as the `yyyy-MM-dd` day key of the broken day.
    func testRepairStreakRecordsTheBrokenDay() async {
        let (sut, _, progress) = makeSUT()
        let brokenDay = madrid.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)) ?? now

        await sut.repairStreak(brokenDay: brokenDay)

        XCTAssertEqual(progress.repairs.map(\.day), [dayKey(9)])
        XCTAssertNil(sut.errorMessage)
    }

    func testRepairFailureShowsTheSpanishMessage() async {
        let (sut, _, progress) = makeSUT()
        progress.failure = FakeProgressDataLoader.FakeError.network

        await sut.repairStreak(brokenDay: now)

        XCTAssertEqual(sut.errorMessage, TodayViewModel.repairFailureMessage)
    }

    func testLoadFailureShowsTheSpanishMessage() async {
        let (sut, today, _) = makeSUT()
        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.errorMessage, TodayViewModel.loadFailureMessage)
        XCTAssertEqual(sut.snapshot, .empty)
        XCTAssertFalse(sut.isLoading)
    }

    /// A failed refresh must not blank the day the user is already looking at.
    func testFailedRefreshKeepsThePreviousDay() async {
        let (sut, today, _) = makeSUT()
        today.dailyScoresResult = .success([dailyScore(day: dayKey(10), score: 87)])
        await sut.load(userID: Self.userID)

        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)
        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.snapshot.score, 87)
        XCTAssertEqual(sut.errorMessage, TodayViewModel.loadFailureMessage)
    }

    func testReloadClearsThePreviousError() async {
        let (sut, today, _) = makeSUT()
        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)
        await sut.load(userID: Self.userID)
        XCTAssertNotNil(sut.errorMessage)

        today.dailyScoresResult = .success([])
        await sut.load(userID: Self.userID)

        XCTAssertNil(sut.errorMessage)
    }
}
