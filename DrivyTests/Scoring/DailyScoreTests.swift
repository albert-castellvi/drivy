import XCTest
@testable import Drivy

/// S6: the daily Driver Score is the distance-weighted average of the day's
/// drives. The same rule feeds `public.daily_scores` (S10).
final class DailyScoreTests: XCTestCase {

    private func input(_ score: Int, _ distanceKm: Double) -> DriveScoreInput {
        DriveScoreInput(score: score, distanceKm: distanceKm)
    }

    func testDailyScoreIsDistanceWeighted() throws {
        // (90 × 3.3 + 60 × 6.7) / 10 = 69.9 → 70, not the plain mean (75).
        let daily = try XCTUnwrap(
            DailyScoreCalculator.dailyScore(from: [input(90, 3.3), input(60, 6.7)])
        )

        XCTAssertEqual(daily.score, 70)
        XCTAssertEqual(daily.distanceKm, 10.0)
        XCTAssertEqual(daily.drivesCount, 2)
    }

    func testEqualDistancesBehaveLikeThePlainAverage() throws {
        let daily = try XCTUnwrap(
            DailyScoreCalculator.dailyScore(from: [input(100, 5), input(60, 5)])
        )

        XCTAssertEqual(daily.score, 80)
        XCTAssertEqual(daily.distanceKm, 10.0)
    }

    func testRoundingIsToTheNearestPoint() throws {
        // 100 × 1 + 60 × 2 = 220 / 3 = 73.33 → 73.
        let daily = try XCTUnwrap(
            DailyScoreCalculator.dailyScore(from: [input(100, 1), input(60, 2)])
        )

        XCTAssertEqual(daily.score, 73)
    }

    func testZeroDistanceDrivesFallBackToThePlainAverage() throws {
        // No distance means no weight: dividing by 0 km must not happen.
        let daily = try XCTUnwrap(
            DailyScoreCalculator.dailyScore(from: [input(100, 0), input(60, 0)])
        )

        XCTAssertEqual(daily.score, 80)
        XCTAssertEqual(daily.distanceKm, 0)
        XCTAssertEqual(daily.drivesCount, 2)
    }

    func testDailyScoreIsClampedToTheValidRange() throws {
        let daily = try XCTUnwrap(DailyScoreCalculator.dailyScore(from: [input(140, 1), input(-20, 1)]))

        XCTAssertEqual(daily.score, 60)
    }

    func testEmptyDayHasNoDailyScore() {
        XCTAssertNil(DailyScoreCalculator.dailyScore(from: []))
    }

    func testSingleDriveIsItsOwnDailyScore() throws {
        let daily = try XCTUnwrap(DailyScoreCalculator.dailyScore(from: [input(88, 12.5)]))

        XCTAssertEqual(daily.score, 88)
        XCTAssertEqual(daily.distanceKm, 12.5)
        XCTAssertEqual(daily.drivesCount, 1)
    }

    func testDriveScoreExposesItsAggregateInput() {
        let score = DriveScore(
            score: 88,
            distanceKm: 12.5,
            durationSeconds: 600,
            harshBrakes: 1,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )

        XCTAssertEqual(score.aggregateInput, DriveScoreInput(score: 88, distanceKm: 12.5))
    }
}
