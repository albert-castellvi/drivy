import XCTest
@testable import Drivy

/// S2 and S12: the finished drive carries the events of the drive so the post-drive
/// summary can draw them, and none of them is ever part of what leaves the phone.
final class DriveRecordEventsTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static let brake = DriveEvent(
        kind: .harshBrake,
        timestamp: 42,
        coordinate: DriveCoordinate(latitude: 41.3874, longitude: 2.1686)
    )

    private func makeScore(
        score: Int = 88,
        distanceKm: Double = 1.5,
        events: [DriveEvent] = []
    ) -> DriveScore {
        DriveScore(
            score: score,
            distanceKm: distanceKm,
            durationSeconds: 100,
            harshBrakes: 1,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: true,
            events: events
        )
    }

    // MARK: - The record carries the events

    func testRecordKeepsTheEventsOfTheScore() {
        let score = makeScore(events: [Self.brake])

        let record = DriveRecord(score: score, startedAt: Self.startedAt)

        XCTAssertEqual(record.events, [Self.brake])
    }

    func testExplicitEventsReplaceTheOnesOfTheScore() {
        let score = makeScore(events: [Self.brake])
        let speeding = DriveEvent(kind: .speeding, timestamp: 10)

        let record = DriveRecord(score: score, startedAt: Self.startedAt, events: [speeding])

        XCTAssertEqual(record.events, [speeding])
    }

    func testRecordWithoutEventsStillDerivesEveryCountedNumber() {
        let record = DriveRecord(score: makeScore(), startedAt: Self.startedAt)

        XCTAssertTrue(record.events.isEmpty)
        XCTAssertEqual(record.score, 88)
        XCTAssertEqual(record.distanceKm, 1.5)
        XCTAssertEqual(record.harshBrakes, 1)
        XCTAssertEqual(record.connectedMode, true)
    }

    // MARK: - Privacy (S10, S12)

    func testUploadPayloadNeverCarriesAnEventNorACoordinate() throws {
        // A drive whose events are perfectly located: the payload must not expose a
        // single one of those coordinates, because they only exist on the phone.
        let record = DriveRecord(
            score: makeScore(events: [
                Self.brake,
                DriveEvent(
                    kind: .speeding,
                    timestamp: 12,
                    coordinate: DriveCoordinate(latitude: 40.4168, longitude: -3.7038)
                )
            ]),
            startedAt: Self.startedAt
        )

        let payload = DriveRowPayload(record: record, userID: "user-1")
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("41.3874"))
        XCTAssertFalse(json.contains("2.1686"))
        XCTAssertFalse(json.contains("40.4168"))
        XCTAssertFalse(json.contains("-3.7038"))
        XCTAssertFalse(json.contains("latitude"))
        XCTAssertFalse(json.contains("longitude"))
        XCTAssertFalse(json.contains("event"))
    }

    func testUploadPayloadKeepsTheCountedNumbersOfTheEvents() throws {
        let record = DriveRecord(
            score: makeScore(events: [Self.brake]),
            startedAt: Self.startedAt
        )

        let payload = DriveRowPayload(record: record, userID: "user-1")

        XCTAssertEqual(payload.harshBrakes, 1)
        XCTAssertEqual(payload.score, 88)
    }
}
