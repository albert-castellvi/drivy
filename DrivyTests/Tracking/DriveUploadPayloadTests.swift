import XCTest
@testable import Drivy

/// The payload is the contract with `public.drives` and `public.daily_scores`
/// (S10, migration `20261027125528_drivy_schema_v1.sql`): these tests pin the exact column names
/// and the values that reach PostgREST, and prove no raw sample is part of it.
final class DriveUploadPayloadTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static let driveColumns: Set<String> = [
        "user_id",
        "started_at",
        "ended_at",
        "distance_km",
        "duration_s",
        "score",
        "harsh_brakes",
        "harsh_accelerations",
        "phone_use_events",
        "speeding_events",
        "connected_mode",
        "summary"
    ]

    private func makeScore(
        score: Int = 88,
        distanceKm: Double = 1.5,
        durationSeconds: TimeInterval = 100,
        harshBrakes: Int = 1,
        harshAccelerations: Int = 2,
        phoneUseEvents: Int = 3,
        speedingEvents: Int = 4,
        connectedMode: Bool = false
    ) -> DriveScore {
        DriveScore(
            score: score,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: connectedMode
        )
    }

    private func makeRecord(_ score: DriveScore) -> DriveRecord {
        DriveRecord(score: score, startedAt: Self.startedAt)
    }

    private func encodedJSON(_ payload: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - drives

    func testDriveRowPayloadUsesTheSchemaColumnNames() throws {
        let payload = DriveRowPayload(record: makeRecord(makeScore()), userID: "user-1")

        XCTAssertEqual(Set(try encodedJSON(payload).keys), Self.driveColumns)
    }

    func testDriveRowPayloadCarriesTheSummarizedCountersOnly() throws {
        let payload = DriveRowPayload(record: makeRecord(makeScore()), userID: "user-1")
        let json = try encodedJSON(payload)

        XCTAssertEqual(json["user_id"] as? String, "user-1")
        XCTAssertEqual(json["distance_km"] as? Double, 1.5)
        XCTAssertEqual(json["duration_s"] as? Int, 100)
        XCTAssertEqual(json["score"] as? Int, 88)
        XCTAssertEqual(json["harsh_brakes"] as? Int, 1)
        XCTAssertEqual(json["harsh_accelerations"] as? Int, 2)
        XCTAssertEqual(json["phone_use_events"] as? Int, 3)
        XCTAssertEqual(json["speeding_events"] as? Int, 4)
        XCTAssertEqual(json["connected_mode"] as? Bool, false)
        // No field can carry a GPS fix or a motion sample: the count of keys is
        // fixed, and there is no array-valued key at all.
        XCTAssertTrue(json.values.allSatisfy { !($0 is [Any]) })
    }

    func testTimestampsAreISO8601InUTC() throws {
        let payload = DriveRowPayload(record: makeRecord(makeScore()), userID: "user-1")
        let json = try encodedJSON(payload)

        XCTAssertEqual(json["started_at"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["ended_at"] as? String, "2023-11-14T22:15:00Z")
        XCTAssertEqual(DriveISO8601.string(from: Self.startedAt), "2023-11-14T22:13:20Z")
    }

    func testDistanceIsRoundedToTwoDecimals() throws {
        let payload = DriveRowPayload(
            record: makeRecord(makeScore(distanceKm: 1.2345)),
            userID: "user-1"
        )
        let json = try encodedJSON(payload)

        XCTAssertEqual(json["distance_km"] as? Double, 1.23)
    }

    func testDurationIsNeverZeroSoTheRowIsValid() throws {
        let record = makeRecord(makeScore(durationSeconds: 0))
        let payload = DriveRowPayload(record: record, userID: "user-1")
        let json = try encodedJSON(payload)

        XCTAssertEqual(record.durationSeconds, 1)
        XCTAssertEqual(record.endedAt, Self.startedAt.addingTimeInterval(1))
        XCTAssertEqual(json["duration_s"] as? Int, 1)
        XCTAssertEqual(json["ended_at"] as? String, "2023-11-14T22:13:21Z")
    }

    func testScoreIsClampedToTheColumnRange() throws {
        let payload = DriveRowPayload(record: makeRecord(makeScore(score: 130)), userID: "user-1")
        let json = try encodedJSON(payload)

        XCTAssertEqual(json["score"] as? Int, 100)
    }

    // MARK: - summary (jsonb)

    func testSummaryHasNoRawSamplesAndDescribesTheEngine() throws {
        let payload = DriveRowPayload(record: makeRecord(makeScore()), userID: "user-1")
        let json = try encodedJSON(payload)
        let summary = try XCTUnwrap(json["summary"] as? [String: Any])

        XCTAssertEqual(
            Set(summary.keys),
            ["engine_version", "phone_penalty_waived", "average_speed_kmh"]
        )
        XCTAssertEqual(summary["engine_version"] as? Int, ScoringRules.version)
        XCTAssertEqual(summary["phone_penalty_waived"] as? Bool, false)
        // 1.5 km in 100 s = 54 km/h.
        XCTAssertEqual(summary["average_speed_kmh"] as? Double, 54)
    }

    func testSummaryMarksTheWaivedPhonePenaltyWhenConnected() throws {
        let record = makeRecord(makeScore(connectedMode: true))
        let payload = DriveRowPayload(record: record, userID: "user-1")
        let json = try encodedJSON(payload)
        let summary = try XCTUnwrap(json["summary"] as? [String: Any])

        XCTAssertTrue(record.summary.phonePenaltyWaived)
        XCTAssertEqual(summary["phone_penalty_waived"] as? Bool, true)
    }

    // MARK: - daily_scores

    func testDailyScoreRowPayloadUsesTheSchemaColumnNames() throws {
        let dailyScore = DailyScore(score: 70, distanceKm: 10.0, drivesCount: 2)
        let payload = DailyScoreRowPayload(dailyScore: dailyScore, userID: "user-1", day: "2023-11-14")
        let json = try encodedJSON(payload)

        XCTAssertEqual(Set(json.keys), ["user_id", "day", "score", "distance_km", "drives_count"])
        XCTAssertEqual(json["user_id"] as? String, "user-1")
        XCTAssertEqual(json["day"] as? String, "2023-11-14")
        XCTAssertEqual(json["score"] as? Int, 70)
        XCTAssertEqual(json["distance_km"] as? Double, 10.0)
        XCTAssertEqual(json["drives_count"] as? Int, 2)
    }
}
