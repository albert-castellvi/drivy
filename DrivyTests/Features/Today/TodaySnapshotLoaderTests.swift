import XCTest
@testable import Drivy

/// The read path of the Hoy tab (S1, S4, S6): today's Driver Score comes from
/// `daily_scores` (or from today's drives when the row is not there yet), the streak
/// is rebuilt from the days that count, and the XP and the quests of the day come
/// from the shared progress layer.
final class TodaySnapshotLoaderTests: XCTestCase {

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

    private func dayKey(_ date: Date) -> String {
        DriveDay.key(for: date, calendar: madrid)
    }

    private func dayKey(_ day: Int, month: Int = 3) -> String {
        let date = madrid.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))
        return dayKey(date ?? now)
    }

    private func drive(
        id: String = "row-1",
        score: Int,
        distanceKm: Double,
        phoneUseEvents: Int = 0,
        connectedMode: Bool = false,
        startedAt: Date? = nil
    ) -> DriveHistoryRow {
        let start = startedAt ?? now
        return DriveHistoryRow(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: score,
            harshBrakes: 0,
            harshAccelerations: 0,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: 0,
            connectedMode: connectedMode
        )
    }

    private func dailyScore(
        day: String,
        score: Int,
        distanceKm: Double = 10,
        drives: Int = 1
    ) -> DailyScoreRecord {
        DailyScoreRecord(day: day, score: score, distanceKm: distanceKm, drivesCount: drives)
    }

    private func load(
        _ today: FakeTodayDataLoader,
        progress: StubProgressDataLoader = StubProgressDataLoader(),
        plan: FreemiumPlan? = nil
    ) async throws -> TodaySnapshot {
        let loader = TodaySnapshotLoader(
            dataLoader: today,
            progressLoader: progress,
            calendar: madrid
        )
        return try await loader.load(userID: "user-1", now: now, plan: plan)
    }

    // MARK: - Score

    func testTodayScoreComesFromTheStoredDailyScore() async throws {
        let today = FakeTodayDataLoader()
        today.dailyScoresResult = .success([dailyScore(day: dayKey(10), score: 87, distanceKm: 12.34)])
        today.drivesResult = .success([drive(score: 80, distanceKm: 5)])

        let snapshot = try await load(today)

        XCTAssertEqual(snapshot.dayKey, dayKey(10))
        XCTAssertEqual(snapshot.score, 87)
        XCTAssertEqual(snapshot.distanceKm, 12.34)
        XCTAssertEqual(snapshot.drivesCount, 1)
        XCTAssertEqual(snapshot.drives.count, 1)
    }

    func testMissingDailyScoreIsComputedFromTodaysDrives() async throws {
        let today = FakeTodayDataLoader()
        today.drivesResult = .success([
            drive(id: "row-1", score: 100, distanceKm: 1),
            drive(id: "row-2", score: 60, distanceKm: 3)
        ])

        let snapshot = try await load(today)

        // (100 × 1 + 60 × 3) / 4 = 70: the same distance-weighted rule as the
        // upload path (S6), not a plain mean (80).
        XCTAssertEqual(snapshot.score, 70)
        XCTAssertEqual(snapshot.distanceKm, 4)
        XCTAssertEqual(snapshot.drivesCount, 2)
    }

    func testEmptyDayHasNoScore() async throws {
        let snapshot = try await load(FakeTodayDataLoader())

        XCTAssertNil(snapshot.score)
        XCTAssertEqual(snapshot.distanceKm, 0)
        XCTAssertEqual(snapshot.drivesCount, 0)
        XCTAssertEqual(snapshot.streak.days, 0)
        XCTAssertFalse(snapshot.hasLessonToday)
    }

    // MARK: - Streak

    func testStreakCountsOnlyTheCleanDays() async throws {
        let today = FakeTodayDataLoader()
        today.dailyScoresResult = .success([
            dailyScore(day: dayKey(10), score: 87),
            dailyScore(day: dayKey(9), score: 70),
            dailyScore(day: dayKey(8), score: 65)
        ])

        let snapshot = try await load(today)

        // The 9th is below the threshold and today is charged to the free freeze,
        // so only the 10th counts and no freeze is left.
        XCTAssertEqual(snapshot.streak.days, 1)
        XCTAssertTrue(snapshot.streak.isTodayCounted)
        XCTAssertEqual(snapshot.streak.freezesLeftThisWeek, 0)
    }

    /// S1: a day whose row is not written yet still counts through the score the
    /// card already shows.
    func testTodaysComputedScoreAlsoCountsForTheStreak() async throws {
        let today = FakeTodayDataLoader()
        today.drivesResult = .success([drive(score: 92, distanceKm: 6)])

        let snapshot = try await load(today)

        XCTAssertEqual(snapshot.score, 92)
        XCTAssertEqual(snapshot.streak.days, 1)
        XCTAssertTrue(snapshot.streak.isTodayCounted)
    }

    /// S1: a day without driving counts when the lesson of the day is done.
    func testLessonDaysCountForTheStreak() async throws {
        let today = FakeTodayDataLoader()
        let progress = StubProgressDataLoader()
        progress.lessonDayKeys = [dayKey(9), dayKey(10)]

        let snapshot = try await load(today, progress: progress)

        XCTAssertEqual(snapshot.streak.days, 2)
        XCTAssertTrue(snapshot.hasLessonToday)
    }

    /// S1/S8: the weekly allowance comes from the plan in force.
    func testTheFreezeAllowanceComesFromThePlan() async throws {
        let premium = try await load(FakeTodayDataLoader(), plan: .premium)
        let free = try await load(FakeTodayDataLoader(), plan: .free)

        XCTAssertEqual(premium.streak.freezesLeftThisWeek, FreemiumLimits.premiumWeeklyFreezes)
        XCTAssertEqual(free.streak.freezesLeftThisWeek, FreemiumLimits.freeWeeklyFreezes)
    }

    /// S8: a repaired day is forgiven, so it does not break the run, and the newest
    /// repair is exposed for the cooldown.
    func testStreakRepairsAreApplied() async throws {
        let today = FakeTodayDataLoader()
        today.dailyScoresResult = .success([
            dailyScore(day: dayKey(10), score: 90),
            dailyScore(day: dayKey(9), score: 50)
        ])
        let progress = StubProgressDataLoader()
        let repairedAt = now.addingTimeInterval(-3_600)
        progress.repairs = [StreakRepairRecord(day: dayKey(9), createdAt: repairedAt)]

        let snapshot = try await load(today, progress: progress)

        XCTAssertEqual(snapshot.streak.days, 2)
        XCTAssertEqual(snapshot.lastStreakRepairAt, repairedAt)
        XCTAssertFalse(snapshot.hasLessonToday)
    }

    // MARK: - XP (S4)

    func testXPIsReadForTheMondayOfTheWeek() async throws {
        let progress = StubProgressDataLoader()
        progress.xpTotals = XPTotals(totalXP: 640, weekXP: 120)

        let snapshot = try await load(FakeTodayDataLoader(), progress: progress)

        XCTAssertEqual(progress.xpWeekStarts, ["2026-03-09"])
        XCTAssertEqual(snapshot.xp, XPTotals(totalXP: 640, weekXP: 120))
    }

    /// A failed XP read hides the card instead of blanking the day or showing 0.
    func testXPFailureOnlyHidesTheXPCard() async throws {
        let progress = StubProgressDataLoader()
        progress.xpError = StubProgressDataLoader.StubError.unavailable

        let snapshot = try await load(FakeTodayDataLoader(), progress: progress)

        XCTAssertNil(snapshot.xp)
    }

    // MARK: - Quests (S6)

    func testTheQuestBoardIsTheOneOfTheDay() async throws {
        let snapshot = try await load(FakeTodayDataLoader())

        XCTAssertEqual(
            snapshot.quests.map(\.quest.id),
            DailyQuestBoard.quests(for: "user-1", dayKey: dayKey(10)).map(\.id)
        )
        XCTAssertEqual(snapshot.quests.count, DailyQuestBoard.dailyCount)
    }

    /// S6: a quest with no car in it is completed by the lesson of the day.
    func testTheLessonCompletesTheLessonQuest() async throws {
        let progress = StubProgressDataLoader()
        progress.lessonDayKeys = [dayKey(10)]

        let snapshot = try await load(FakeTodayDataLoader(), progress: progress)

        let lesson = try XCTUnwrap(snapshot.quests.first { $0.quest.id == QuestCatalog.lesson.id })
        XCTAssertTrue(lesson.isCompleted)
        XCTAssertTrue(snapshot.pendingQuestIDs.contains(QuestCatalog.lesson.id))
    }

    func testAnAlreadyStoredQuestIsNotPendingAgain() async throws {
        let progress = StubProgressDataLoader()
        progress.lessonDayKeys = [dayKey(10)]
        progress.storedQuestIDs = [QuestCatalog.lesson.id]

        let snapshot = try await load(FakeTodayDataLoader(), progress: progress)

        XCTAssertTrue(snapshot.pendingQuestIDs.isEmpty)
        XCTAssertTrue(snapshot.quests.contains { $0.quest.id == QuestCatalog.lesson.id && $0.isCompleted })
    }

    /// S6: one clean drive of the day satisfies every driving quest of the board
    /// that asks for what that drive did, and the lesson quest stays pending.
    func testAQuestIsCompletedByAQualifyingDriveOfTheDay() async throws {
        let today = FakeTodayDataLoader()
        today.drivesResult = .success([
            drive(score: 95, distanceKm: 5, phoneUseEvents: 0, connectedMode: true)
        ])

        let snapshot = try await load(today)

        let driving = snapshot.quests.filter { $0.quest.requirement.needsDriving }
        XCTAssertFalse(driving.isEmpty)
        XCTAssertTrue(driving.allSatisfy(\.isCompleted))
        XCTAssertFalse(
            try XCTUnwrap(snapshot.quests.first { $0.quest.id == QuestCatalog.lesson.id }).isCompleted
        )
    }

    // MARK: - Queries

    func testDailyScoresAreReadFromTheWholeStreakWindow() async throws {
        let today = FakeTodayDataLoader()

        _ = try await load(today)

        let call = try XCTUnwrap(today.dailyScoresCalls.first)
        let expectedFirstDay = madrid.date(
            byAdding: .day,
            value: -TodaySnapshotLoader.streakHistoryDays,
            to: now
        ) ?? now

        XCTAssertEqual(call.userID, "user-1")
        XCTAssertEqual(call.to, dayKey(10))
        XCTAssertEqual(call.from, dayKey(expectedFirstDay))
    }

    func testDrivesAreReadFromTheLocalDay() async throws {
        let today = FakeTodayDataLoader()

        _ = try await load(today)

        let call = try XCTUnwrap(today.drivesCalls.first)
        let dayStart = madrid.startOfDay(for: now)
        XCTAssertEqual(call.userID, "user-1")
        XCTAssertEqual(call.dayStart, dayStart)
        XCTAssertEqual(call.dayEnd, madrid.date(byAdding: .day, value: 1, to: dayStart))
    }

    func testLessonsAreReadFromTheWholeStreakWindow() async throws {
        let progress = StubProgressDataLoader()

        _ = try await load(FakeTodayDataLoader(), progress: progress)

        let call = try XCTUnwrap(progress.lessonDayCalls.first)
        XCTAssertEqual(call.to, dayKey(10))
    }

    func testQuestsAreReadForToday() async throws {
        let progress = StubProgressDataLoader()

        _ = try await load(FakeTodayDataLoader(), progress: progress)

        XCTAssertEqual(progress.questDays, [dayKey(10)])
    }

    // MARK: - Failures

    func testAReadFailureIsThrown() async {
        let today = FakeTodayDataLoader()
        today.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        do {
            _ = try await load(today)
            XCTFail("Expected the read failure to be thrown")
        } catch {
            XCTAssertEqual(error as? FakeTodayDataLoader.FakeError, .network)
        }
    }

    func testDriveReadFailureIsThrown() async {
        let today = FakeTodayDataLoader()
        today.drivesResult = .failure(FakeTodayDataLoader.FakeError.network)

        do {
            _ = try await load(today)
            XCTFail("Expected the read failure to be thrown")
        } catch {
            XCTAssertEqual(error as? FakeTodayDataLoader.FakeError, .network)
        }
    }

    /// The streak cannot be computed without the lesson days, so that failure is a
    /// failure of the day and not a silently wrong streak.
    func testLessonReadFailureIsThrown() async {
        let progress = StubProgressDataLoader()
        progress.lessonDaysError = StubProgressDataLoader.StubError.unavailable

        do {
            _ = try await load(FakeTodayDataLoader(), progress: progress)
            XCTFail("Expected the read failure to be thrown")
        } catch {
            XCTAssertEqual(error as? StubProgressDataLoader.StubError, .unavailable)
        }
    }
}
