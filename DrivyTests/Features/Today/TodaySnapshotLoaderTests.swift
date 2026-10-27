import XCTest
@testable import Drivy

/// The read path of the Today tab (S6): today's Driver Score comes from
/// `daily_scores` (or from today's drives when the row is not there yet) and the
/// streak is rebuilt from the days that have drives.
final class TodaySnapshotLoaderTests: XCTestCase {

    /// 2023-11-14T22:13:20Z, i.e. 2023-11-14 in UTC.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func drive(
        id: String = "row-1",
        score: Int,
        distanceKm: Double,
        startedAt: Date = TodaySnapshotLoaderTests.now
    ) -> DriveHistoryRow {
        DriveHistoryRow(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: score,
            harshBrakes: 0,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
    }

    private func dailyScore(day: String, score: Int, distanceKm: Double = 10, drives: Int = 1) -> DailyScoreRecord {
        DailyScoreRecord(day: day, score: score, distanceKm: distanceKm, drivesCount: drives)
    }

    private func load(_ fake: FakeTodayDataLoader) async throws -> TodaySnapshot {
        let loader = TodaySnapshotLoader(dataLoader: fake, calendar: utc)
        return try await loader.load(userID: "user-1", now: Self.now)
    }

    // MARK: - Score

    func testTodayScoreComesFromTheStoredDailyScore() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([dailyScore(day: "2023-11-14", score: 87, distanceKm: 12.34)])
        fake.drivesResult = .success([drive(score: 80, distanceKm: 5)])

        let snapshot = try await load(fake)

        XCTAssertEqual(snapshot.dayKey, "2023-11-14")
        XCTAssertEqual(snapshot.score, 87)
        XCTAssertEqual(snapshot.distanceKm, 12.34)
        XCTAssertEqual(snapshot.drivesCount, 1)
        XCTAssertEqual(snapshot.drives.count, 1)
    }

    func testMissingDailyScoreIsComputedFromTodaysDrives() async throws {
        let fake = FakeTodayDataLoader()
        fake.drivesResult = .success([
            drive(id: "row-1", score: 100, distanceKm: 1),
            drive(id: "row-2", score: 60, distanceKm: 3)
        ])

        let snapshot = try await load(fake)

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
        XCTAssertEqual(snapshot.streak, .empty)
    }

    // MARK: - Streak

    func testStreakComesFromTheDaysWithDrives() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([
            dailyScore(day: "2023-11-14", score: 87),
            dailyScore(day: "2023-11-13", score: 70),
            dailyScore(day: "2023-11-12", score: 65)
        ])

        let snapshot = try await load(fake)

        XCTAssertEqual(snapshot.streak.days, 3)
        XCTAssertTrue(snapshot.streak.isTodayRecorded)
    }

    func testStreakSkipsDaysStoredWithoutDrives() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([
            dailyScore(day: "2023-11-14", score: 87),
            dailyScore(day: "2023-11-13", score: 0, distanceKm: 0, drives: 0),
            dailyScore(day: "2023-11-12", score: 65)
        ])

        let snapshot = try await load(fake)

        // The empty row is the grace day, not a counted day.
        XCTAssertEqual(snapshot.streak.days, 2)
        XCTAssertTrue(snapshot.streak.usesGraceDay)
    }

    // MARK: - Queries

    func testDailyScoresAreReadFromTheWholeStreakWindow() async throws {
        let fake = FakeTodayDataLoader()

        _ = try await load(fake)

        let call = try XCTUnwrap(fake.dailyScoresCalls.first)
        XCTAssertEqual(call.userID, "user-1")
        XCTAssertEqual(call.to, "2023-11-14")
        XCTAssertEqual(
            call.from,
            dayKey(utc.date(byAdding: .day, value: -400, to: Self.now) ?? Self.now)
        )
    }

    func testDrivesAreReadFromTheLocalDay() async throws {
        let fake = FakeTodayDataLoader()

        _ = try await load(fake)

        let call = try XCTUnwrap(fake.drivesCalls.first)
        let dayStart = utc.startOfDay(for: Self.now)
        XCTAssertEqual(call.userID, "user-1")
        XCTAssertEqual(call.dayStart, dayStart)
        XCTAssertEqual(call.dayEnd, utc.date(byAdding: .day, value: 1, to: dayStart))
    }

    // MARK: - Failures

    func testAReadFailureIsThrown() async {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        do {
            _ = try await load(fake)
            XCTFail("Expected the read failure to be thrown")
        } catch {
            XCTAssertEqual(error as? FakeTodayDataLoader.FakeError, .network)
        }
    }

    func testDriveReadFailureIsThrown() async {
        let fake = FakeTodayDataLoader()
        fake.drivesResult = .failure(FakeTodayDataLoader.FakeError.network)

        do {
            _ = try await load(fake)
            XCTFail("Expected the read failure to be thrown")
        } catch {
            XCTAssertEqual(error as? FakeTodayDataLoader.FakeError, .network)
        }
    }
}
