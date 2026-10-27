import XCTest
@testable import Drivy

/// Scoring v1 (S5, S13): every threshold boundary, the per-km weighting and the
/// full 0–100 composition, exercised through the public engine only.
///
/// Drives are built so that 1 km of distance lines up with the point scale: at
/// 10 m/s for 100 s the trapezoidal integration gives exactly 1000 m, so a drive
/// with one harsh brake reads as 100 − 12 = 88 points.
final class ScoringEngineTests: XCTestCase {

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

    private func motions(_ accelerations: [Double]) -> [MotionSample] {
        accelerations.enumerated().map { index, acceleration in
            MotionSample(timestamp: TimeInterval(index), longitudinalAcceleration: acceleration)
        }
    }

    private func drive(
        locations: [LocationSample]? = nil,
        motions: [Double] = [],
        phoneUseEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveSamples {
        DriveSamples(
            locations: locations ?? constantLocations(),
            motions: self.motions(motions),
            phoneUseEvents: phoneUseEvents,
            connectedMode: connectedMode
        )
    }

    private func score(
        _ samples: DriveSamples,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DriveScore {
        try XCTUnwrap(engine.score(samples), "expected a score for a drive with fixes", file: file, line: line)
    }

    // MARK: - Baseline

    func testPerfectDriveScoresOneHundred() throws {
        let result = try score(drive())

        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.distanceKm, 1.0)
        XCTAssertEqual(result.durationSeconds, 100)
        XCTAssertEqual(result.harshBrakes, 0)
        XCTAssertEqual(result.harshAccelerations, 0)
        XCTAssertEqual(result.phoneUseEvents, 0)
        XCTAssertEqual(result.speedingEvents, 0)
        XCTAssertFalse(result.connectedMode)
        XCTAssertFalse(result.isPhoneUsePenaltyWaived)
    }

    func testDriveWithoutFixesHasNoScore() {
        XCTAssertNil(engine.score(DriveSamples()))
        XCTAssertNil(engine.score(DriveSamples(motions: motions([-9]), phoneUseEvents: 3)))
    }

    func testDistanceIsIntegratedFromTheFixes() throws {
        // 0 → 10 m/s over 10 s: trapezoid = 50 m.
        let locations = [
            LocationSample(timestamp: 0, speedMetersPerSecond: 0, speedLimitKmh: nil),
            LocationSample(timestamp: 10, speedMetersPerSecond: 10, speedLimitKmh: nil)
        ]

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.distanceKm, 0.05, accuracy: 1e-9)
        XCTAssertEqual(result.durationSeconds, 10)
    }

    func testInvalidGPSspeedIsTreatedAsNoMovement() throws {
        let locations = [
            LocationSample(timestamp: 0, speedMetersPerSecond: -1, speedLimitKmh: nil),
            LocationSample(timestamp: 10, speedMetersPerSecond: -1, speedLimitKmh: nil)
        ]

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.distanceKm, 0)
        XCTAssertEqual(result.score, 100)
    }

    // MARK: - Harsh braking (S5: "desaceleración > 3.5 m/s²")

    func testHarshBrakingAtThresholdIsNotAViolation() throws {
        let result = try score(drive(motions: [-3.5]))

        XCTAssertEqual(result.harshBrakes, 0)
        XCTAssertEqual(result.score, 100)
    }

    func testHarshBrakingJustAboveThresholdIsAViolation() throws {
        let result = try score(drive(motions: [-3.51]))

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.harshAccelerations, 0)
        XCTAssertEqual(result.score, 88)
    }

    func testOneHardBrakeIsCountedOnceAcrossManySensorSamples() throws {
        let result = try score(drive(motions: [-4.2, -4.5, -4.1, -4.0, -3.8]))

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.score, 88)
    }

    func testSecondHardBrakeIsCountedOnceTheSignalIsReleased() throws {
        let result = try score(drive(motions: [-4.2, -1.0, -4.2]))

        XCTAssertEqual(result.harshBrakes, 2)
        XCTAssertEqual(result.score, 76)
    }

    func testShortDipBelowTheThresholdDoesNotSplitOneEvent() throws {
        // -3.6 is above the release level (-2.45), so it is still the same brake.
        let result = try score(drive(motions: [-4.2, -3.6, -4.2]))

        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.score, 88)
    }

    // MARK: - Harsh acceleration (S5: "> 3.0 m/s²")

    func testHarshAccelerationAtThresholdIsNotAViolation() throws {
        let result = try score(drive(motions: [3.0]))

        XCTAssertEqual(result.harshAccelerations, 0)
        XCTAssertEqual(result.score, 100)
    }

    func testHarshAccelerationJustAboveThresholdIsAViolation() throws {
        let result = try score(drive(motions: [3.01]))

        XCTAssertEqual(result.harshAccelerations, 1)
        XCTAssertEqual(result.harshBrakes, 0)
        XCTAssertEqual(result.score, 92)
    }

    func testBrakingIsNeverCountedAsAccelerationAndViceVersa() throws {
        let braking = try score(drive(motions: [-3.6]))
        let accelerating = try score(drive(motions: [3.6]))

        XCTAssertEqual(braking.harshBrakes, 1)
        XCTAssertEqual(braking.harshAccelerations, 0)
        XCTAssertEqual(accelerating.harshBrakes, 0)
        XCTAssertEqual(accelerating.harshAccelerations, 1)
    }

    // MARK: - Phone use (S5)

    func testPhoneUseDuringTheDriveIsPenalized() throws {
        let result = try score(drive(phoneUseEvents: 1))

        XCTAssertEqual(result.phoneUseEvents, 1)
        XCTAssertEqual(result.score, 75)
    }

    func testTwoPhoneUseEventsArePenalizedCumulatively() throws {
        let result = try score(drive(phoneUseEvents: 2))

        XCTAssertEqual(result.score, 50)
    }

    // MARK: - Speeding (S5: "umbral +10 km/h")

    func testSpeedingAtThresholdIsNotAViolation() throws {
        // 60 km/h limit, exactly 70 km/h: the threshold is "more than +10".
        let locations = constantLocations(speed: 70.0 / 3.6, speedLimitKmh: 60)

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 0)
        XCTAssertEqual(result.score, 100)
    }

    func testSpeedingJustAboveThresholdIsAViolation() throws {
        // 72 km/h against a 60 km/h limit, 1 km of drive.
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.distanceKm, 1.0)
        XCTAssertEqual(result.speedingEvents, 1)
        XCTAssertEqual(result.score, 90)
    }

    func testSpeedingWithoutAKnownLimitIsIgnored() throws {
        let locations = constantLocations(speed: 40, speedLimitKmh: nil)

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 0)
        XCTAssertEqual(result.score, 100)
    }

    func testContinuousSpeedingIsOneEvent() throws {
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 1)
    }

    func testSpeedingIsCountedAgainAfterDroppingWellBelowTheLimit() throws {
        // 72 → 45 → 72 km/h against a 60 km/h limit: down 27 km/h is a release.
        let locations = [
            LocationSample(timestamp: 0, speedMetersPerSecond: 20, speedLimitKmh: 60),
            LocationSample(timestamp: 10, speedMetersPerSecond: 12.5, speedLimitKmh: 60),
            LocationSample(timestamp: 20, speedMetersPerSecond: 20, speedLimitKmh: 60)
        ]

        let result = try score(drive(locations: locations))

        XCTAssertEqual(result.speedingEvents, 2)
    }

    // MARK: - Per-km weighting (S5: "penalizaciones acumulativas ponderadas por km")

    func testPenaltiesAreWeightedPerKilometre() throws {
        // One brake in 1 km and two brakes in 2 km are the same density.
        let shortDrive = try score(drive(motions: [-4.2]))
        let longDrive = try score(
            drive(
                locations: constantLocations(speed: 10, duration: 200, step: 20),
                motions: [-4.2, -1.0, -4.2]
            )
        )

        XCTAssertEqual(shortDrive.distanceKm, 1.0)
        XCTAssertEqual(longDrive.distanceKm, 2.0)
        XCTAssertEqual(longDrive.harshBrakes, 2)
        XCTAssertEqual(longDrive.score, 88)
        XCTAssertEqual(shortDrive.score, longDrive.score)
    }

    func testShortDrivesUseTheMinimumDistance() throws {
        // 50 m with one harsh acceleration: 8 points / 0.1 km = 80 → 20.
        // Without the minimum-distance guard it would divide by 0.05 and hit 0.
        let locations = [
            LocationSample(timestamp: 0, speedMetersPerSecond: 10, speedLimitKmh: nil),
            LocationSample(timestamp: 5, speedMetersPerSecond: 10, speedLimitKmh: nil)
        ]

        let result = try score(drive(locations: locations, motions: [3.01]))

        XCTAssertEqual(result.distanceKm, 0.05, accuracy: 1e-9)
        XCTAssertEqual(result.score, 20)
    }

    // MARK: - Full composition (S5)

    func testEveryPenaltyStacksOnTheSameDrive() throws {
        // 1 km at 72 km/h with a 60 km/h limit: one braking, one acceleration,
        // one phone-use and one speeding event.
        // 100 − (12 + 8 + 25 + 10) = 45.
        let locations = constantLocations(speed: 20, duration: 50, step: 5, speedLimitKmh: 60)

        let result = try score(
            drive(locations: locations, motions: [-4.2, 3.5], phoneUseEvents: 1)
        )

        XCTAssertEqual(result.distanceKm, 1.0)
        XCTAssertEqual(result.harshBrakes, 1)
        XCTAssertEqual(result.harshAccelerations, 1)
        XCTAssertEqual(result.phoneUseEvents, 1)
        XCTAssertEqual(result.speedingEvents, 1)
        XCTAssertEqual(result.score, 45)
    }

    func testScoreNeverGoesBelowZero() throws {
        // 0.2 km with three brakes: 36 points / 0.2 km = 180 → clamped to 0.
        let locations = constantLocations(speed: 10, duration: 20, step: 2)

        let result = try score(drive(locations: locations, motions: [-4.2, -1.0, -4.2, -1.0, -4.2]))

        XCTAssertEqual(result.harshBrakes, 3)
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - Connected driving (S13)

    func testConnectedModeWaivesThePhoneUsePenalty() throws {
        let result = try score(drive(motions: [-4.2], phoneUseEvents: 2, connectedMode: true))

        XCTAssertEqual(result.phoneUseEvents, 2, "the count is kept, only the penalty is waived")
        XCTAssertEqual(result.connectedMode, true)
        XCTAssertEqual(result.isPhoneUsePenaltyWaived, true)
        // 100 − 12 (braking) + 5 (connected bonus); the 2 phone events are free.
        XCTAssertEqual(result.score, 93)
    }

    func testPhoneUseIsPenalizedWhenNotConnected() throws {
        let result = try score(drive(motions: [-4.2], phoneUseEvents: 2, connectedMode: false))

        // 100 − 12 − 50 = 38.
        XCTAssertEqual(result.score, 38)
        XCTAssertFalse(result.isPhoneUsePenaltyWaived)
    }

    func testConnectedBonusIsCappedAtOneHundred() throws {
        let result = try score(drive(phoneUseEvents: 1, connectedMode: true))

        XCTAssertEqual(result.phoneUseEvents, 1)
        XCTAssertEqual(result.score, 100)
    }
}
