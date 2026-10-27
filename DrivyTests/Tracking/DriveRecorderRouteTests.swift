import CoreLocation
import XCTest
@testable import Drivy

/// Route exposure of the recorder (L11).
///
/// The route is all the drive detail screen can ever draw (S10: the samples never
/// leave the phone), so the recorder must expose the coordinates of the finished
/// drive and never mix two drives together.
@MainActor
final class DriveRecorderRouteTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

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
            now: { DriveRecorderRouteTests.startDate }
        )
        return SUT(recorder: recorder, location: location, motion: motion, uploader: uploader)
    }

    /// 1 km drive plus its route, i.e. something the engine can score.
    private func emitScorableDrive(_ sut: SUT, coordinates: [CLLocationCoordinate2D]) {
        sut.location.emit(FakeLocationSampler.constantDrive())
        sut.location.emit(coordinates: coordinates)
    }

    // MARK: - While recording

    func testRouteIsEmptyBeforeAnyFix() {
        let sut = makeSUT()

        XCTAssertTrue(sut.recorder.routeCoordinates.isEmpty)

        sut.recorder.start()

        XCTAssertTrue(sut.recorder.routeCoordinates.isEmpty)
    }

    func testRouteFollowsTheCoordinatesOfTheFixes() {
        let sut = makeSUT()
        sut.recorder.start()
        let route = FakeLocationSampler.straightRoute(count: 3)

        sut.location.emit(coordinates: route)

        XCTAssertEqual(sut.recorder.routeCoordinates.count, 3)
        XCTAssertEqual(sut.recorder.routeCoordinates.map(\.latitude), route.map(\.latitude))
        XCTAssertEqual(sut.recorder.routeCoordinates.map(\.longitude), route.map(\.longitude))
    }

    func testCoordinatesReceivedWhileIdleAreIgnored() {
        let sut = makeSUT()

        sut.location.emit(coordinates: FakeLocationSampler.straightRoute(count: 4))

        XCTAssertTrue(sut.recorder.routeCoordinates.isEmpty)
    }

    // MARK: - After a drive

    func testRouteStaysAvailableNextToTheFinishedDrive() async {
        let sut = makeSUT()
        let route = FakeLocationSampler.straightRoute(count: 12)
        sut.recorder.start()
        emitScorableDrive(sut, coordinates: route)

        await sut.recorder.stop()

        // The screen that reacts to `lastCompletedDrive` reads the route afterwards,
        // so it must survive `stop()`.
        XCTAssertNotNil(sut.recorder.lastCompletedDrive)
        XCTAssertEqual(sut.recorder.routeCoordinates.count, 12)
    }

    func testRouteIsNotKeptWhenTheDriveCannotBeScored() async {
        let sut = makeSUT()
        sut.recorder.start()
        // Coordinates without a single scoring sample: nothing to score, nothing to
        // draw.
        sut.location.emit(coordinates: FakeLocationSampler.straightRoute(count: 5))

        await sut.recorder.stop()

        XCTAssertNil(sut.recorder.lastCompletedDrive)
        XCTAssertTrue(sut.recorder.routeCoordinates.isEmpty)
    }

    func testStartingANewDriveClearsThePreviousRoute() async {
        let sut = makeSUT()
        sut.recorder.start()
        emitScorableDrive(sut, coordinates: FakeLocationSampler.straightRoute(count: 8))
        await sut.recorder.stop()
        XCTAssertEqual(sut.recorder.routeCoordinates.count, 8)

        sut.recorder.start()

        XCTAssertTrue(sut.recorder.routeCoordinates.isEmpty)
    }

    // MARK: - Sensor boundary

    func testStopDetachesTheCoordinateCallback() async {
        let sut = makeSUT()
        sut.recorder.start()

        await sut.recorder.stop()

        XCTAssertNil(sut.location.onCoordinate)
    }
}
