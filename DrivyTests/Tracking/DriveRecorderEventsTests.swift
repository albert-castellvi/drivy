import CoreLocation
import XCTest
@testable import Drivy

/// S2 at the seam between the device and the summary: the recorder is the only
/// place where the samples and the route of one drive meet, so it is where the
/// events of a finished drive get their position. They stay on the phone (S10,
/// S12): the upload payload is asserted in `DriveRecordEventsTests`.
@MainActor
final class DriveRecorderEventsTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// First point of `FakeLocationSampler.straightRoute()`.
    private static let firstRoutePoint = DriveCoordinate(latitude: 41.3874, longitude: 2.1686)

    private struct SUT {
        let recorder: DriveRecorder
        let location: FakeLocationSampler
        let motion: FakeMotionSampler
        let uploader: FakeDriveUploader
    }

    private func makeSUT() -> SUT {
        let location = FakeLocationSampler()
        let motion = FakeMotionSampler()
        let uploader = FakeDriveUploader()

        let recorder = DriveRecorder(
            locationSampler: location,
            motionSampler: motion,
            connectedModeDetector: FakeConnectedModeDetector(),
            uploader: uploader,
            pendingStore: PendingDriveStore(directory: Self.makePendingDirectory()),
            now: { DriveRecorderEventsTests.startDate }
        )
        return SUT(recorder: recorder, location: location, motion: motion, uploader: uploader)
    }

    /// Fresh store directory per SUT, so no test sees another test's pending
    /// records.
    private static func makePendingDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DriveRecorderEventsTests-pending-\(UUID().uuidString)", isDirectory: true)
    }

    /// 1 km at 10 m/s with one harsh brake and the route of the same fixes.
    private func emitOneKilometreDriveWithABrakeAndRoute(_ sut: SUT) {
        sut.motion.emit([-4.2], startingAt: 0)
        sut.location.emit(FakeLocationSampler.constantDrive())
        sut.location.emit(coordinates: FakeLocationSampler.straightRoute(count: 11))
    }

    // MARK: - Positioned events

    func testFinishedDriveCarriesThePositionedEventOfTheRoute() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrakeAndRoute(sut)

        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.recorder.lastCompletedDrive)
        XCTAssertEqual(record.harshBrakes, 1)
        XCTAssertEqual(record.events.count, 1)

        let brake = try XCTUnwrap(record.events.first)
        XCTAssertEqual(brake.kind, .harshBrake)
        XCTAssertEqual(brake.timestamp, 0)
        XCTAssertEqual(brake.coordinate, Self.firstRoutePoint)
    }

    func testFinishedDriveWithoutARouteKeepsTheEventsWithoutCoordinate() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        sut.motion.emit([-4.2], startingAt: 0)
        sut.location.emit(FakeLocationSampler.constantDrive())

        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.recorder.lastCompletedDrive)
        let brake = try XCTUnwrap(record.events.first)
        XCTAssertEqual(brake.kind, .harshBrake)
        XCTAssertNil(brake.coordinate)
    }

    func testEventsOfTheFinishedDriveMatchItsCounts() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrakeAndRoute(sut)
        sut.recorder.registerPhoneUseEvent()

        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.recorder.lastCompletedDrive)
        XCTAssertEqual(
            record.events.count,
            record.harshBrakes + record.harshAccelerations + record.speedingEvents + record.phoneUseEvents
        )
        XCTAssertEqual(record.events.filter { $0.kind == .phoneUse }.count, record.phoneUseEvents)
    }

    // MARK: - One drive at a time

    func testANewDriveDoesNotKeepTheEventsOfThePreviousOne() async throws {
        let sut = makeSUT()
        sut.recorder.start()
        emitOneKilometreDriveWithABrakeAndRoute(sut)
        await sut.recorder.stop()

        sut.recorder.start()
        // Second drive: no harsh brake, so no event at all.
        sut.location.emit(FakeLocationSampler.constantDrive())
        sut.location.emit(coordinates: FakeLocationSampler.straightRoute(count: 11))
        await sut.recorder.stop()

        let record = try XCTUnwrap(sut.recorder.lastCompletedDrive)
        XCTAssertEqual(record.harshBrakes, 0)
        XCTAssertTrue(record.events.isEmpty)
    }

    func testStopWithoutFixesStillEndsTheSessionWithNoEvents() async {
        let sut = makeSUT()
        sut.recorder.start()

        await sut.recorder.stop()

        XCTAssertNil(sut.recorder.lastCompletedDrive)
        XCTAssertTrue(sut.uploader.uploadedRecords.isEmpty)
    }
}
