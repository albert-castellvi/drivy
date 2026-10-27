import XCTest
@testable import Drivy

/// S2: what the 30-second summary shows. The model is a pure value built from the
/// finished drive, so the sheet has no rules of its own and everything the user
/// reads is asserted here.
final class DebriefSummaryTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static let locatedBrake = DriveEvent(
        kind: .harshBrake,
        timestamp: 10,
        coordinate: DriveCoordinate(latitude: 41.3874, longitude: 2.1686)
    )

    private static let locatedSpeeding = DriveEvent(
        kind: .speeding,
        timestamp: 30,
        coordinate: DriveCoordinate(latitude: 41.3900, longitude: 2.1700)
    )

    private static let unlocatedPhoneUse = DriveEvent(kind: .phoneUse)

    private func makeRecord(
        score: Int = 76,
        distanceKm: Double = 12.5,
        durationSeconds: TimeInterval = 900,
        harshBrakes: Int = 1,
        harshAccelerations: Int = 2,
        phoneUseEvents: Int = 1,
        speedingEvents: Int = 1,
        connectedMode: Bool = false,
        events: [DriveEvent] = []
    ) -> DriveRecord {
        let driveScore = DriveScore(
            score: score,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: connectedMode,
            events: events
        )
        return DriveRecord(score: driveScore, startedAt: Self.startedAt)
    }

    // MARK: - Counts per kind

    func testEventRowsCoverEveryKindInAFixedOrder() {
        let summary = DebriefSummary(record: makeRecord())

        XCTAssertEqual(summary.eventRows.map(\.kind), DriveEventKind.allCases)
        XCTAssertEqual(summary.eventRows.map(\.count), [1, 2, 1, 1])
        XCTAssertEqual(summary.eventRows.map(\.id), ["harshBrake", "harshAcceleration", "speeding", "phoneUse"])
    }

    func testCleanDriveStillShowsEveryKindAtZero() {
        let summary = DebriefSummary(
            record: makeRecord(
                harshBrakes: 0,
                harshAccelerations: 0,
                phoneUseEvents: 0,
                speedingEvents: 0
            )
        )

        XCTAssertEqual(summary.eventRows.map(\.count), [0, 0, 0, 0])
        XCTAssertEqual(summary.tip, .clean)
    }

    // MARK: - Markers

    func testOnlyEventsWithAKnownPositionBecomeMarkers() {
        let summary = DebriefSummary(
            record: makeRecord(events: [
                Self.locatedBrake,
                Self.unlocatedPhoneUse,
                Self.locatedSpeeding
            ])
        )

        XCTAssertEqual(summary.markers.map(\.kind), [.harshBrake, .speeding])
        XCTAssertEqual(summary.markers.map(\.id), [0, 2])
        XCTAssertEqual(summary.markers.first?.coordinate, Self.locatedBrake.coordinate)
    }

    func testDriveWithoutARouteHasNoMarkers() {
        let summary = DebriefSummary(
            record: makeRecord(
                events: [
                    DriveEvent(kind: .harshBrake, timestamp: 10),
                    DriveEvent(kind: .speeding, timestamp: 20)
                ]
            )
        )

        XCTAssertTrue(summary.markers.isEmpty)
        // The counts are facts of the drive and never depend on the route.
        XCTAssertEqual(summary.eventRows.map(\.count), [1, 2, 1, 1])
    }

    // MARK: - Score, advice and connected note

    func testSummaryMirrorsTheRecordAndItsAdvice() {
        let record = makeRecord()

        let summary = DebriefSummary(record: record)

        XCTAssertEqual(summary.score, 76)
        XCTAssertEqual(summary.distanceKm, 12.5)
        XCTAssertEqual(summary.durationSeconds, 900)
        XCTAssertEqual(summary.tip, DebriefTip.tip(for: record))
    }

    func testConnectedDriveExplainsThatPhoneUseWasNotPenalized() {
        let summary = DebriefSummary(record: makeRecord(connectedMode: true))

        XCTAssertEqual(
            summary.connectedNote,
            "Conducción conectada: el uso del móvil no ha penalizado."
        )
        XCTAssertEqual(summary.connectedNote, DebriefSummary.connectedModeNote)
    }

    func testDriveWithoutConnectionHasNoConnectedNote() {
        let summary = DebriefSummary(record: makeRecord(connectedMode: false))

        XCTAssertNil(summary.connectedNote)
    }
}
