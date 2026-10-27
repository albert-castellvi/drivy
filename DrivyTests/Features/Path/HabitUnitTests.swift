import XCTest
@testable import Drivy

/// Units of the habit path (S3): the five rules, their database keys and the order
/// the path plays them in.
final class HabitUnitTests: XCTestCase {

    private func drive(
        distanceKm: Double = 5,
        harshBrakes: Int = 0,
        harshAccelerations: Int = 0,
        phoneUseEvents: Int = 0,
        speedingEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveHistoryRow {
        let start = Date(timeIntervalSince1970: 1_772_000_000)
        return DriveHistoryRow(
            id: "row-1",
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

    // MARK: - The five rules

    func testSmoothBrakingNeedsADriveWithoutHarshBrakes() {
        XCTAssertTrue(HabitUnit.smoothBraking.isQualified(drive(harshBrakes: 0)))
        XCTAssertFalse(HabitUnit.smoothBraking.isQualified(drive(harshBrakes: 1)))
    }

    func testSmoothAccelerationNeedsADriveWithoutHarshAccelerations() {
        XCTAssertTrue(HabitUnit.smoothAcceleration.isQualified(drive(harshAccelerations: 0)))
        XCTAssertFalse(HabitUnit.smoothAcceleration.isQualified(drive(harshAccelerations: 1)))
    }

    func testNoPhoneNeedsADriveWithoutPhoneUseEvents() {
        XCTAssertTrue(HabitUnit.noPhone.isQualified(drive(phoneUseEvents: 0)))
        XCTAssertFalse(HabitUnit.noPhone.isQualified(drive(phoneUseEvents: 1)))
    }

    func testSpeedNeedsADriveWithoutSpeedingEvents() {
        XCTAssertTrue(HabitUnit.speed.isQualified(drive(speedingEvents: 0)))
        XCTAssertFalse(HabitUnit.speed.isQualified(drive(speedingEvents: 1)))
    }

    /// S3: "Conducción conectada" is the only unit that asks for something to be
    /// on, not for an event to be absent.
    func testConnectedNeedsADriveRecordedInConnectedMode() {
        XCTAssertTrue(HabitUnit.connected.isQualified(drive(connectedMode: true)))
        XCTAssertFalse(HabitUnit.connected.isQualified(drive(connectedMode: false)))
    }

    /// Every unit judges its own metric only: a drive with a phone event is still a
    /// smooth-braking drive, so one bad habit never blocks another unit.
    func testAUnitIgnoresTheMetricsOfTheOtherUnits() {
        let badAtEverythingButBraking = drive(
            harshBrakes: 0,
            harshAccelerations: 4,
            phoneUseEvents: 2,
            speedingEvents: 3,
            connectedMode: false
        )

        XCTAssertTrue(HabitUnit.smoothBraking.isQualified(badAtEverythingButBraking))
        XCTAssertFalse(HabitUnit.smoothAcceleration.isQualified(badAtEverythingButBraking))
        XCTAssertFalse(HabitUnit.noPhone.isQualified(badAtEverythingButBraking))
        XCTAssertFalse(HabitUnit.speed.isQualified(badAtEverythingButBraking))
        XCTAssertFalse(HabitUnit.connected.isQualified(badAtEverythingButBraking))
    }

    // MARK: - Keys of the database

    /// `public.habit_levels.unit` accepts exactly these five values, so the raw
    /// values and their order are the contract with `0002_duolingo_loop.sql`.
    func testKeysMatchTheDatabaseAndThePathOrder() {
        XCTAssertEqual(
            HabitUnit.allCases.map(\.rawValue),
            ["smooth_braking", "smooth_acceleration", "no_phone", "speed", "connected"]
        )
        XCTAssertEqual(HabitUnit.smoothBraking.id, HabitUnit.smoothBraking.rawValue)
    }

    // MARK: - The chain of the path

    func testEveryUnitOpensAfterThePreviousOne() {
        XCTAssertNil(HabitUnit.smoothBraking.previous)
        XCTAssertEqual(HabitUnit.smoothAcceleration.previous, .smoothBraking)
        XCTAssertEqual(HabitUnit.noPhone.previous, .smoothAcceleration)
        XCTAssertEqual(HabitUnit.speed.previous, .noPhone)
        XCTAssertEqual(HabitUnit.connected.previous, .speed)
    }

    // MARK: - Copy

    /// S3 names the units, so the titles are asserted verbatim.
    func testTitlesAreTheOnesTheSpecNames() {
        XCTAssertEqual(HabitUnit.smoothBraking.title, "Frenada suave")
        XCTAssertEqual(HabitUnit.smoothAcceleration.title, "Arranque suave")
        XCTAssertEqual(HabitUnit.noPhone.title, "Cero móvil")
        XCTAssertEqual(HabitUnit.speed.title, "Velocidad")
        XCTAssertEqual(HabitUnit.connected.title, "Conducción conectada")
    }

    func testEveryUnitHasATipAndASymbol() {
        for unit in HabitUnit.allCases {
            XCTAssertFalse(unit.tip.isEmpty, "\(unit.rawValue) has no tip")
            XCTAssertFalse(unit.symbolName.isEmpty, "\(unit.rawValue) has no symbol")
        }
    }
}
