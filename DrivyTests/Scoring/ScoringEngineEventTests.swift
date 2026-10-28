import XCTest
@testable import Drivy

/// S2: the engine also returns the events it counted — which kind, when, and where
/// when the route of the device is available — without touching a single score,
/// threshold, weight or count of S5. These tests pin both sides at once, so a drift
/// between the count of a drive and its events cannot pass unnoticed.
final class ScoringEngineEventTests: XCTestCase {

    private let engine = ScoringEngine()

    // MARK: - Helpers

    /// Constant-speed drive. Default: 10 m/s during 100 s = exactly 1 km.
    private func constantLocations(
        speed: Double = 10,
        duration: TimeInterval = 100,
        step: TimeInterval = 10,
        speedLimitKmh: Double? = nil
    ) -> [LocationSample] {
        var locations: [LocationSample] = []
        var time: TimeInterval = 0
        while time <= duration + 1e-9 {
            locations.append(
                LocationSample(
                    timestamp: time,
                    speedMetersPerSecond: speed,
                    speedLimitKmh: speedLimitKmh
                )
            )
            time += step
        }
        return locations
    }

    private func motions(
        _ accelerations: [Double],
        startingAt time: TimeInterval = 0,
        step: TimeInterval = 1
    ) -> [MotionSample] {
        accelerations.enumerated().map { index, acceleration in
            MotionSample(
                timestamp: time + TimeInterval(index) * step,
                longitudinalAcceleration: acceleration
            )
        }
    }

    private func drive(
        locations: [LocationSample]? = nil,
        motions: [Double] = [],
        motionStart: TimeInterval = 0,
        motionStep: TimeInterval = 1,
        phoneUseEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveSamples {
        DriveSamples(
            locations: locations ?? constantLocations(),
            motions: self.motions(motions, startingAt: motionStart, step: motionStep),
            phoneUseEvents: phoneUseEvents,
            connectedMode: connectedMode
        )
    }

    /// One coordinate per fix, distinguished by latitude, so an event points at
    /// exactly one index of the route.
    private func route(_ count: Int) -> [DriveCoordinate] {
        (0..<count).map { index in
            DriveCoordinate(latitude: 41.0 + Double(index) / 1000, longitude: 2.0)
        }
    }

    private func score(
        _ samples: DriveSamples,
        route: [DriveCoordinate] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DriveScore {
        try XCTUnwrap(
            engine.score(samples, route: route),
            "expected a score for a drive with fixes",
            file: file,
            line: line
        )
    }

    private func events(of kind: DriveEventKind, in score: DriveScore) -> [DriveEvent] {
        score.events.filter { $0.kind == kind }
    }

    // MARK: - Baseline

    func testPerfectDriveReportsNoEvents() throws {
        let result = try score(drive())

        XCTAssertEqual(result.score, 100)
        XCTAssertTrue(result.events.isEmpty)
    }

    // MARK: - Harsh braking (S5: "desaceleración > 3.5 m/s²")

    func testHarshBrakeEventKeepsTheTimestampOfTheSampleThatCrossed() throws {
        let result = try score(drive(motions: [-4.2], motionStart: 50))

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.score, 88)

        let brakes = events(of: .harshBrake, in: result)
        XCTAssertEqual(brakes.count, 1)
        XCTAssertEqual(brakes.first?.timestamp, 50)
        XCTAssertNil(brakes.first?.coordinate)
    }

    func testOneHardBrakeAcrossManySamplesIsOneEvent() throws {
        let result = try score(drive(motions: [-4.2, -4.5, -4.1, -4.0, -3.8]))

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(events(of: .harshBrake, in: result).count, 1)
    }

    func testSecondBrakeAfterAReleaseIsASecondEventWithItsOwnTime() throws {
        let result = try score(drive(motions: [-4.2, -1.0, -4.2]))

        XCTAssertEqual(result.harshBrakes, 2)
        let brakes = events(of: .harshBrake, in: result)
        XCTAssertEqual(brakes.map(\.timestamp), [0, 2] as [TimeInterval?])
    }

    // MARK: - Harsh acceleration (S5: "> 3.0 m/s²")

    func testHarshAccelerationEventIsReportedAsItsOwnKind() throws {
        let result = try score(drive(motions: [3.01], motionStart: 30))

        XCTAssertEqual(result.harshAccelerations, 1)
        XCTAssertEqual(result.score, 92)

        let accelerations = events(of: .harshAcceleration, in: result)
        XCTAssertEqual(accelerations.count, 1)
        XCTAssertEqual(accelerations.first?.timestamp, 30)
        XCTAssertTrue(events(of: .harshBrake, in: result).isEmpty)
    }

    func testBrakingIsNeverReportedAsAcceleration() throws {
        let result = try score(drive(motions: [-3.6]))

        XCTAssertTrue(events(of: .harshAcceleration, in: result).isEmpty)
        XCTAssertEqual(events(of: .harshBrake, in: result).count, 1)
    }

    // MARK: - Phone use (S5)

    func testPhoneUseEventsHaveNoPositionInTime() throws {
        let result = try score(drive(phoneUseEvents: 2))

        XCTAssertEqual(result.phoneUseEvents, 2)
        XCTAssertEqual(result.score, 50)

        let phoneEvents = events(of: .phoneUse, in: result)
        XCTAssertEqual(phoneEvents.count, 2)
        XCTAssertEqual(phoneEvents.map(\.timestamp), [nil, nil])
        XCTAssertEqual(phoneEvents.map(\.coordinate), [nil, nil])
    }

    // MARK: - Speeding (S5: "umbral +10 km/h")

    func testSpeedingEventIsStampedWithTheFixThatExceeded() throws {
        // 72 km/h against a 60 km/h limit, one km of drive.
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 1)
        XCTAssertEqual(result.score, 90)

        let speeding = events(of: .speeding, in: result)
        XCTAssertEqual(speeding.count, 1)
        XCTAssertEqual(speeding.first?.timestamp, 0)
    }

    func testSpeedingIsReportedAgainAfterDroppingWellBelowTheLimit() throws {
        let locations = [
            LocationSample(timestamp: 0, speedMetersPerSecond: 20, speedLimitKmh: 60),
            LocationSample(timestamp: 10, speedMetersPerSecond: 12.5, speedLimitKmh: 60),
            LocationSample(timestamp: 20, speedMetersPerSecond: 20, speedLimitKmh: 60)
        ]

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 2)
        XCTAssertEqual(events(of: .speeding, in: result).map(\.timestamp), [0, 20] as [TimeInterval?])
    }

    func testSpeedingWithoutAKnownLimitProducesNoEvent() throws {
        let locations = constantLocations(speed: 40, speedLimitKmh: nil)

        let result = try score(drive(locations: locations))

        XCTAssertTrue(events(of: .speeding, in: result).isEmpty)
    }

    // MARK: - Positions (S2)

    func testEventCoordinateIsTheFixNearestInTime() throws {
        // Fixes every 10 s from 0 to 100; the brake happens at 52 s, so the fix at
        // 50 s (index 5) is the closest one.
        let locations = constantLocations()
        let result = try score(drive(motions: [-4.2], motionStart: 52), route: route(locations.count))

        let brake = try XCTUnwrap(events(of: .harshBrake, in: result).first)
        XCTAssertEqual(brake.coordinate, route(locations.count)[5])
    }

    func testSpeedingEventPointsAtTheFixThatOpenedIt() throws {
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)
        let result = try score(drive(locations: locations), route: route(locations.count))

        let speeding = try XCTUnwrap(events(of: .speeding, in: result).first)
        XCTAssertEqual(speeding.coordinate, route(locations.count)[0])
    }

    func testExamplePositionsAreFoundForEveryKindOnTheSameDrive() throws {
        // 1 km at 72 km/h with a 60 km/h limit: one braking, one acceleration and
        // one speeding event, all located on the same route.
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)
        let result = try score(
            drive(locations: locations, motions: [-4.2, 3.5], motionStep: 5),
            route: route(locations.count)
        )

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.harshAccelerations, 1)
        XCTAssertEqual(result.speedingEvents, 1)
        XCTAssertEqual(result.events.count, 3)
        XCTAssertTrue(result.events.allSatisfy { $0.coordinate != nil })
    }

    func testCoordinateIsMissingWhenTheRouteIsShorterThanTheFixes() throws {
        // The route of this device can be incomplete (a lost fix): an event must
        // stay unpositioned instead of pointing at the wrong place.
        let locations = constantLocations()
        let result = try score(
            drive(motions: [-4.2], motionStart: 95),
            route: route(3)
        )

        let brake = try XCTUnwrap(events(of: .harshBrake, in: result).first)
        XCTAssertNil(brake.coordinate)
        XCTAssertEqual(brake.timestamp, 95)
    }

    // MARK: - The route never changes the score (S2)

    func testRouteNeverChangesTheScoreOrTheCounts() throws {
        let samples = drive(
            locations: constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60),
            motions: [-4.2, -1.0, 3.5],
            motionStep: 10,
            phoneUseEvents: 1
        )

        let withoutRoute = try score(samples)
        let withRoute = try score(samples, route: route(samples.locations.count))

        XCTAssertEqual(withRoute.score, withoutRoute.score)
        XCTAssertEqual(withRoute.distanceKm, withoutRoute.distanceKm)
        XCTAssertEqual(withRoute.durationSeconds, withoutRoute.durationSeconds)
        XCTAssertEqual(withRoute.harshBrakes, withoutRoute.harshBrakes)
        XCTAssertEqual(withRoute.harshAccelerations, withoutRoute.harshAccelerations)
        XCTAssertEqual(withRoute.phoneUseEvents, withoutRoute.phoneUseEvents)
        XCTAssertEqual(withRoute.speedingEvents, withoutRoute.speedingEvents)
        XCTAssertEqual(withRoute.events.count, withoutRoute.events.count)
    }

    // MARK: - Order and completeness

    func testEventsAreInTimeOrderAndCoverEveryCountedEvent() throws {
        let samples = drive(motions: [3.01, -1.0, -4.2], motionStart: 20, motionStep: 10)

        let result = try score(samples)

        XCTAssertEqual(result.harshAccelerations, 1)
        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.events.map(\.kind), [.harshAcceleration, .harshBrake])
        XCTAssertEqual(result.events.map(\.timestamp), [20, 40] as [TimeInterval?])
    }

    func testEveryEventOfTheScoreIsAccountedForByKind() throws {
        let samples = drive(
            locations: constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60),
            motions: [-4.2, -1.0, 3.5],
            phoneUseEvents: 2
        )

        let result = try score(samples)

        XCTAssertEqual(events(of: .harshBrake, in: result).count, result.harshBrakes)
        XCTAssertEqual(events(of: .harshAcceleration, in: result).count, result.harshAccelerations)
        XCTAssertEqual(events(of: .speeding, in: result).count, result.speedingEvents)
        XCTAssertEqual(events(of: .phoneUse, in: result).count, result.phoneUseEvents)
        XCTAssertEqual(
            result.events.count,
            result.harshBrakes
                + result.harshAccelerations
                + result.speedingEvents
                + result.phoneUseEvents
        )
    }
}
