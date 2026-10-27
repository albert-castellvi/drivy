import XCTest
@testable import Drivy

/// The recorder is the seam between the device and the pure engine: these tests
/// drive it with fake sensors and assert what the UI sees and what would be
/// uploaded (S4, S5, S10, S13).
@MainActor
final class DriveRecorderTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    private struct SUT {
        let recorder: DriveRecorder
        let location: FakeLocationSampler
        let motion: FakeMotionSampler
        let detector: FakeConnectedModeDetector
        let uploader: FakeDriveUploader
    }

    private func makeSUT() -> SUT {
        let location = FakeLocationSampler()
        let motion = FakeMotionSampler()
        let detector = FakeConnectedModeDetector()
        let uploader = FakeDriveUploader()

        let recorder = DriveRecorder(
            locationSampler: location,
            motionSampler: motion,
            connectedModeDetector: detector,
            uploader: uploader,
            now: { DriveRecorderTests.startDate }
        )
        return SUT(
            recorder: recorder,
            location: location,
            motion: motion,
            detector: detector,
            uploader: uploader
        )
    }

    /// 1 km at 10 m/s with one harsh brake: 100 − 12 = 88 points.
    private func emitOneKilometreDriveWithABrake(_ sut: SUT) {
        sut.motion.emit([-4.2], startingAt: 50)
        sut.location.emit(FakeLocationSampler.constantDrive())
    }

    // MARK: - Start

    func testStartBeginsRecordingAndStartsTheSensors() {
        let sut = makeSUT()

        sut.recorder.start()

        XCTAssertTrue(sut.recorder.isRecording)
        XCTAssertEqual(sut.recorder.startedAt, Self.startDate)
        XCTAssertEqual(sut.location.startCount, 1)
        XCTAssertEqual(sut.motion.startCount, 1)
        XCTAssertEqual(sut.detector.startCount, 1)
        XCTAssertNil(sut.recorder.errorMessage)
    }

    func testStartIsIgnoredWhileAlreadyRecording() {
        let sut = makeSUT()

        sut.recorder.start()
        sut.recorder.start()

        XCTAssertEqual(sut.location.startCount, 1)
        XCTAssertEqual(sut.motion.startCount, 1)
        XCTAssertEqual(sut.recorder.startedAt, Self.startDate)
    }

    func testStartWithoutLocationPermissionDoesNotRecord() {
        let sut = makeSUT()
        sut.location.isDenied = true

        sut.recorder.start()

        XCTAssertFalse(sut.recorder.isRecording)
        XCTAssertEqual(sut.recorder.errorMessage, DriveRecorder.locationDeniedMessage)
        XCTAssertEqual(sut.recorder.errorMessage, "Activa la ubicación en Ajustes para registrar trayectos.")
        XCTAssertEqual(sut.location.startCount, 0)
        XCTAssertEqual(sut.motion.startCount, 0)
    }

    // MARK: - Live state

    func testLiveStateFollowsTheSamples() {
        let sut = makeSUT()
        sut.recorder.start()

        // First fix only: there is a drive, but no distance yet.
        sut.location.emit([
            LocationSample(timestamp: 0, speedMetersPerSecond: 10, speedLimitKmh: nil)
        ])
        XCTAssertEqual(sut.recorder.liveScore, 100)
        XCTAssertEqual(sut.recorder.distanceKm, 0)

        // Motion events are folded in on the next fix: re-scoring on every 10 Hz
        // motion sample would be far too expensive.
        sut.motion.emit([-4.2], startingAt: 50)
        sut.location.emit(Array(FakeLocationSampler.constantDrive().dropFirst()))

        XCTAssertEqual(sut.recorder.distanceKm, 1.0)
        XCTAssertEqual(sut.recorder.liveScore, 88)
    }

    func testElapsedUsesTheInjectedClock() {
        let sut = makeSUT()

        XCTAssertEqual(sut.recorder.elapsed(at: Self.startDate), 0)

        sut.recorder.start()

        XCTAssertEqual(sut.recorder.elapsed(at: Self.startDate.addingTimeInterval(42)), 42)
        XCTAssertEqual(sut.recorder.elapsed(at: Self.startDate), 0)
    }

    // MARK: - Phone use (S5)

    func testPhoneUseIsCountedOnlyWhileRecording() async throws {
        let sut = makeSUT()

        sut.recorder.registerPhoneUseEvent() // before the drive: ignored
        sut.recorder.start()
        sut.recorder.registerPhoneUseEvent()
        sut.recorder.registerPhoneUseEvent()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        sut.recorder.registerPhoneUseEvent() // after the drive: ignored

        let record = try XCTUnwrap(sut.uploader.uploadedRecords.first)
        XCTAssertEqual(record.phoneUseEvents, 2)
    }

    func testPhoneUseDuringTheDriveIsPenalizedInTheUploadedDrive() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)
        sut.recorder.registerPhoneUseEvent()

        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.uploader.uploadedRecords.first)
        XCTAssertEqual(record.phoneUseEvents, 1)
        // 100 − 12 (braking) − 25 (phone) = 63.
        XCTAssertEqual(record.score, 63)
        XCTAssertEqual(record.summary.phonePenaltyWaived, false)
    }

    // MARK: - Connected driving (S13)

    func testConnectedModeIsReadAtStart() {
        let sut = makeSUT()
        sut.detector.isConnected = true

        sut.recorder.start()

        XCTAssertTrue(sut.recorder.connectedMode)
    }

    func testConnectedModeChangesDuringTheDriveAreObserved() {
        let sut = makeSUT()
        sut.recorder.start()

        sut.detector.change(to: true)

        XCTAssertTrue(sut.recorder.connectedMode)
    }

    func testConnectedModeWaivesThePhoneUsePenaltyInTheUploadedDrive() async throws {
        let sut = makeSUT()
        sut.detector.isConnected = true
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)
        sut.recorder.registerPhoneUseEvent()
        sut.recorder.registerPhoneUseEvent()

        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.uploader.uploadedRecords.first)
        XCTAssertEqual(record.connectedMode, true)
        XCTAssertEqual(record.phoneUseEvents, 2)
        XCTAssertEqual(record.summary.phonePenaltyWaived, true)
        // 100 − 12 (braking) + 5 (connected bonus); phone use is free (S13).
        XCTAssertEqual(record.score, 93)
    }

    // MARK: - Stop and upload (S10)

    func testStopUploadsTheSummarizedDrive() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        XCTAssertEqual(sut.uploader.uploadedRecords.count, 1)
        let record = try XCTUnwrap(sut.uploader.uploadedRecords.first)

        XCTAssertEqual(record.score, 88)
        XCTAssertEqual(record.distanceKm, 1.0)
        XCTAssertEqual(record.durationSeconds, 100)
        XCTAssertEqual(record.harshBrakes, 1)
        XCTAssertEqual(record.harshAccelerations, 0)
        XCTAssertEqual(record.phoneUseEvents, 0)
        XCTAssertEqual(record.speedingEvents, 0)
        XCTAssertEqual(record.connectedMode, false)
        XCTAssertEqual(record.startedAt, Self.startDate)
        XCTAssertEqual(record.endedAt, Self.startDate.addingTimeInterval(100))
        XCTAssertEqual(record.summary.engineVersion, ScoringRules.version)
        XCTAssertEqual(record.summary.averageSpeedKmh, 36)
        XCTAssertFalse(sut.recorder.isRecording)
        XCTAssertFalse(sut.recorder.isSaving)
    }

    func testStopKeepsTheSummaryOfTheFinishedDrive() async {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        XCTAssertNil(sut.recorder.startedAt)
        XCTAssertEqual(sut.recorder.lastCompletedDrive?.score, 88)
        XCTAssertEqual(sut.recorder.liveScore, 88)
        XCTAssertEqual(sut.recorder.distanceKm, 1.0)
        XCTAssertEqual(sut.recorder.elapsed(at: Self.startDate.addingTimeInterval(10)), 0)
    }

    func testStopWithoutFixesUploadsNothingAndShowsNoSummary() async {
        let sut = makeSUT()
        sut.recorder.start()

        await sut.recorder.stop()

        XCTAssertEqual(sut.uploader.uploadedRecords.count, 0)
        XCTAssertNil(sut.recorder.lastCompletedDrive)
        XCTAssertNil(sut.recorder.liveScore)
        XCTAssertEqual(sut.recorder.distanceKm, 0)
        XCTAssertNil(sut.recorder.errorMessage)
        XCTAssertFalse(sut.recorder.isRecording)
    }

    func testUploadFailureShowsTheExactMessage() async {
        let sut = makeSUT()
        sut.uploader.error = FakeDriveUploader.FakeError.network
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        XCTAssertEqual(sut.uploader.uploadedRecords.count, 0)
        XCTAssertEqual(sut.recorder.errorMessage, DriveRecorder.uploadFailureMessage)
        XCTAssertEqual(sut.recorder.errorMessage, "No hemos podido subir el trayecto.")
        XCTAssertFalse(sut.recorder.isSaving)
        XCTAssertEqual(sut.recorder.lastCompletedDrive?.score, 88)
    }

    func testStopStopsAndDetachesTheSensors() async {
        let sut = makeSUT()
        sut.recorder.start()

        await sut.recorder.stop()

        XCTAssertEqual(sut.location.stopCount, 1)
        XCTAssertEqual(sut.motion.stopCount, 1)
        XCTAssertEqual(sut.detector.stopCount, 1)
        XCTAssertNil(sut.location.onSample)
        XCTAssertNil(sut.motion.onSample)
        XCTAssertNil(sut.detector.onChange)
    }

    func testStopIsIgnoredWhenNotRecording() async {
        let sut = makeSUT()

        await sut.recorder.stop()

        XCTAssertEqual(sut.uploader.uploadedRecords.count, 0)
        XCTAssertEqual(sut.location.stopCount, 0)
        XCTAssertNil(sut.recorder.errorMessage)
    }

    func testStartingANewDriveClearsThePreviousSummary() async {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)
        await sut.recorder.stop()

        sut.recorder.start()

        XCTAssertTrue(sut.recorder.isRecording)
        XCTAssertNil(sut.recorder.lastCompletedDrive)
        XCTAssertNil(sut.recorder.liveScore)
        XCTAssertEqual(sut.recorder.distanceKm, 0)
        XCTAssertEqual(sut.recorder.startedAt, Self.startDate)
    }

    func testSamplesReceivedWhileIdleAreIgnored() {
        let sut = makeSUT()

        sut.location.emit(FakeLocationSampler.constantDrive())
        sut.motion.emit([-9])

        XCTAssertEqual(sut.recorder.distanceKm, 0)
        XCTAssertNil(sut.recorder.liveScore)
    }
}
