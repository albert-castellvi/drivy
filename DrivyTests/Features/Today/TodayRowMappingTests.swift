import XCTest
@testable import Drivy

/// The row types of the Today tab must match the schema column names verbatim
/// (S10): PostgREST returns exactly what the migration declares.
final class TodayRowMappingTests: XCTestCase {

    private func decodeDrive() throws -> DriveHistoryRow {
        try PostgrestFixtures.decode(DriveHistoryRow.self, from: PostgrestFixtures.driveRowJSON)
    }

    func testDriveRowMapsTheSchemaColumns() throws {
        let row = try decodeDrive()

        XCTAssertEqual(row.id, "0b0d1f4e-1111-4222-8333-944455556666")
        XCTAssertEqual(row.distanceKm, 12.34)
        XCTAssertEqual(row.durationSeconds, 1110)
        XCTAssertEqual(row.score, 87)
        XCTAssertEqual(row.harshBrakes, 2)
        XCTAssertEqual(row.harshAccelerations, 1)
        XCTAssertEqual(row.phoneUseEvents, 0)
        XCTAssertEqual(row.speedingEvents, 3)
        XCTAssertTrue(row.connectedMode)
    }

    func testDriveRowParsesTheTimestampWithFractionalSeconds() throws {
        let row = try decodeDrive()

        XCTAssertEqual(
            row.startedAt.timeIntervalSince1970,
            1_700_000_000.123456,
            accuracy: 0.001
        )
        XCTAssertEqual(row.endedAt.timeIntervalSince1970, 1_700_001_110.654321, accuracy: 0.01)
    }

    func testDriveRowAcceptsADistanceSentAsAString() throws {
        let json = """
        {
          "id": "row-1",
          "started_at": "2023-11-14T22:13:20+00:00",
          "ended_at": "2023-11-14T22:31:50+00:00",
          "distance_km": "7.25",
          "duration_s": 1110,
          "score": 74,
          "harsh_brakes": 0,
          "harsh_accelerations": 0,
          "phone_use_events": 0,
          "speeding_events": 0,
          "connected_mode": false
        }
        """

        let row = try PostgrestFixtures.decode(DriveHistoryRow.self, from: json)

        XCTAssertEqual(row.distanceKm, 7.25)
        XCTAssertEqual(row.startedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 0.5)
    }

    func testDriveRowRejectsAnUnparsableTimestamp() {
        let json = """
        {
          "id": "row-1",
          "started_at": "not a date",
          "ended_at": "2023-11-14T22:31:50+00:00",
          "distance_km": 1.0,
          "duration_s": 60,
          "score": 80,
          "harsh_brakes": 0,
          "harsh_accelerations": 0,
          "phone_use_events": 0,
          "speeding_events": 0,
          "connected_mode": false
        }
        """

        XCTAssertThrowsError(try PostgrestFixtures.decode(DriveHistoryRow.self, from: json))
    }

    func testDriveRowExposesTheAggregateInputOfTheDailyAverage() throws {
        let row = try decodeDrive()

        XCTAssertEqual(row.aggregateInput, DriveScoreInput(score: 87, distanceKm: 12.34))
    }

    func testDailyScoreRowMapsTheSchemaColumns() throws {
        let row = try PostgrestFixtures.decode(
            DailyScoreRecord.self,
            from: PostgrestFixtures.dailyScoreRowJSON
        )

        XCTAssertEqual(row.day, "2023-11-14")
        XCTAssertEqual(row.score, 87)
        XCTAssertEqual(row.distanceKm, 12.34)
        XCTAssertEqual(row.drivesCount, 1)
    }

    func testDailyScoreRowAcceptsANumericDistance() throws {
        let json = #"{"day": "2023-11-13", "score": 70, "distance_km": 4.5, "drives_count": 2}"#

        let row = try PostgrestFixtures.decode(DailyScoreRecord.self, from: json)

        XCTAssertEqual(row.distanceKm, 4.5)
        XCTAssertEqual(row.drivesCount, 2)
    }

    func testTimestampAcceptsBothSerializations() {
        let plain = PostgrestTimestamp.date(from: "2023-11-14T22:13:20Z")
        let fractional = PostgrestTimestamp.date(from: "2023-11-14T22:13:20.500000+00:00")

        XCTAssertEqual(plain?.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(fractional?.timeIntervalSince1970 ?? 0, 1_700_000_000.5, accuracy: 0.001)
        XCTAssertNil(PostgrestTimestamp.date(from: "14/11/2023"))
    }
}
