import XCTest
@testable import Drivy

/// D4: a failed upload must never lose the finished drive. The recorder
/// persists the record before uploading and removes it only on success; the
/// retry drains the backlog oldest first, stops at the first failure and never
/// uploads another user's drive.
@MainActor
final class DriveRecorderPendingUploadTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let sessionUserID = "session-user"

    private struct SUT {
        let recorder: DriveRecorder
        let location: FakeLocationSampler
        let motion: FakeMotionSampler
        let uploader: FakeDriveUploader
        let store: PendingDriveStore
    }

    private func makeSUT() -> SUT {
        let location = FakeLocationSampler()
        let motion = FakeMotionSampler()
        let uploader = FakeDriveUploader()
        let store = PendingDriveStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("DriveRecorderPendingTests-\(UUID().uuidString)", isDirectory: true)
        )

        let recorder = DriveRecorder(
            uploader: uploader,
            pendingStore: store,
            now: { Self.startDate }
        )
        return SUT(recorder: recorder, location: location, motion: motion, uploader: uploader, store: store)
    }

    /// 1 km at 10 m/s with one harsh brake: 100 − 12 = 88 points.
    private func emitOneKilometreDriveWithABrake(_ sut: SUT) {
        sut.motion.emit([-4.2], startingAt: 50)
        sut.location.emit(FakeLocationSampler.constantDrive())
    }

    private func makeRecord(startedAt: Date) -> DriveRecord {
        DriveRecord(
            score: DriveScore(
                score: 88,
                distanceKm: 1.0,
                durationSeconds: 100,
                harshBrakes: 0,
                harshAccelerations: 0,
                phoneUseEvents: 0,
                speedingEvents: 0,
                connectedMode: false
            ),
            startedAt: startedAt
        )
    }

    // MARK: - Stop

    func testFailedUploadKeepsTheRecordPendingAndTheMessageUnchanged() async {
        let sut = makeSUT()
        sut.uploader.error = FakeDriveUploader.FakeError.network
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        XCTAssertEqual(sut.recorder.errorMessage, DriveRecorder.uploadFailureMessage)
        XCTAssertEqual(sut.recorder.errorMessage, "No hemos podido subir el trayecto.")
        XCTAssertEqual(sut.uploader.uploadedRecords.count, 0)

        let pending = sut.store.all()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.record.score, 88)
        XCTAssertEqual(pending.first?.record.startedAt, Self.startDate)
        XCTAssertEqual(pending.first?.sessionUserID, Self.sessionUserID)
    }

    func testSuccessfulUploadRemovesThePendingRecord() async {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrake(sut)

        await sut.recorder.stop()

        XCTAssertEqual(sut.uploader.uploadedRecords.count, 1)
        XCTAssertEqual(sut.store.all().count, 0)
    }

    // MARK: - Retry

    func testRetryUploadsPendingDrivesOldestFirstAndStopsAtTheFirstFailure() async throws {
        let sut = makeSUT()
        let oldest = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))
        let middle = makeRecord(startedAt: Date(timeIntervalSince1970: 2_000))
        let newest = makeRecord(startedAt: Date(timeIntervalSince1970: 3_000))
        try sut.store.add(PendingDriveUpload(record: newest, sessionUserID: Self.sessionUserID))
        try sut.store.add(PendingDriveUpload(record: middle, sessionUserID: Self.sessionUserID))
        try sut.store.add(PendingDriveUpload(record: oldest, sessionUserID: Self.sessionUserID))
        sut.uploader.failingIDs = [middle.id]

        await sut.recorder.retryPendingUploads()

        XCTAssertEqual(sut.uploader.uploadedRecords.map(\.id), [oldest.id, middle.id])
        XCTAssertFalse(sut.store.contains(id: oldest.id))
        XCTAssertTrue(sut.store.contains(id: middle.id))
        XCTAssertTrue(sut.store.contains(id: newest.id))
    }

    func testRetryIsIdempotentForDrivesTheServerAlreadyHas() async throws {
        let sut = makeSUT()
        let record = makeRecord(startedAt: Self.startDate)
        try sut.store.add(PendingDriveUpload(record: record, sessionUserID: Self.sessionUserID))
        // The server already stored this drive on an earlier attempt.
        sut.uploader.storedIDs = [record.id]

        await sut.recorder.retryPendingUploads()

        // Treated as success: no second row, and the entry leaves the store.
        XCTAssertTrue(sut.uploader.uploadedRecords.isEmpty)
        XCTAssertFalse(sut.store.contains(id: record.id))
    }

    func testRetryKeepsAnotherUsersPendingDrive() async throws {
        let sut = makeSUT()
        let record = makeRecord(startedAt: Self.startDate)
        try sut.store.add(PendingDriveUpload(record: record, sessionUserID: "someone-else"))

        await sut.recorder.retryPendingUploads()

        XCTAssertTrue(sut.uploader.uploadedRecords.isEmpty)
        XCTAssertTrue(sut.store.contains(id: record.id))
    }

    func testRetryWithoutAResolvableSessionUploadsNothing() async throws {
        let sut = makeSUT()
        let record = makeRecord(startedAt: Self.startDate)
        try sut.store.add(PendingDriveUpload(record: record, sessionUserID: Self.sessionUserID))
        sut.uploader.sessionUserID = nil

        await sut.recorder.retryPendingUploads()

        XCTAssertTrue(sut.uploader.uploadedRecords.isEmpty)
        XCTAssertTrue(sut.store.contains(id: record.id))
    }

    func testRetryNeverTouchesTheLiveDrive() async throws {
        let sut = makeSUT()
        let record = makeRecord(startedAt: Self.startDate)
        try sut.store.add(PendingDriveUpload(record: record, sessionUserID: Self.sessionUserID))
        sut.recorder.start()
        sut.location.emit([
            LocationSample(timestamp: 0, speedMetersPerSecond: 10, speedLimitKmh: nil)
        ])

        await sut.recorder.retryPendingUploads()

        XCTAssertTrue(sut.recorder.isRecording)
        XCTAssertEqual(sut.recorder.startedAt, Self.startDate)
        XCTAssertNil(sut.recorder.errorMessage)
        // The pending drive was uploaded; the live session was not disturbed.
        XCTAssertEqual(sut.uploader.uploadedRecords.map(\.id), [record.id])
    }

    func testRetryIsNotRunTwiceAtTheSameTime() async throws {
        let sut = makeSUT()
        let record = makeRecord(startedAt: Self.startDate)
        try sut.store.add(PendingDriveUpload(record: record, sessionUserID: Self.sessionUserID))

        async let first: Void = sut.recorder.retryPendingUploads()
        async let second: Void = sut.recorder.retryPendingUploads()
        _ = await (first, second)

        // Both drains run, but the record must be uploaded exactly once.
        XCTAssertEqual(sut.uploader.uploadedRecords.count, 1)
        XCTAssertEqual(sut.store.all().count, 0)
    }
}
