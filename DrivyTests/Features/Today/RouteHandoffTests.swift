import CoreLocation
import XCTest
@testable import Drivy

/// L11: the route of a finished drive has to reach `LocalRouteStore` under the key
/// the drive detail screen looks it up with, otherwise the map keeps showing the
/// "no route on this device" state.
final class RouteHandoffTests: XCTestCase {

    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func route(_ count: Int) -> [CLLocationCoordinate2D] {
        FakeLocationSampler.straightRoute(count: count)
    }

    func testARouteIsStoredUnderTheDriveStartTimestamp() {
        let store = LocalRouteStore()

        let stored = RouteHandoff.store(
            coordinates: route(5),
            startedAt: Self.startedAt,
            in: store
        )

        XCTAssertTrue(stored)
        let track = store.track(forStartedAt: Self.startedAt)
        XCTAssertEqual(track?.coordinates.count, 5)
        XCTAssertEqual(track?.coordinates.map(\.latitude), route(5).map(\.latitude))
    }

    func testTheDetailScreenFindsTheStoredRoute() {
        let store = LocalRouteStore()
        RouteHandoff.store(coordinates: route(3), startedAt: Self.startedAt, in: store)

        // Same key rule the screens use (`DriveTrack.key(forStartedAt:)`).
        XCTAssertNotNil(store.track(forStartedAt: Self.startedAt))
        XCTAssertNil(store.track(forStartedAt: Self.startedAt.addingTimeInterval(1)))
    }

    func testASinglePointIsNotADrawableRoute() {
        let store = LocalRouteStore()

        let stored = RouteHandoff.store(
            coordinates: route(1),
            startedAt: Self.startedAt,
            in: store
        )

        XCTAssertFalse(stored)
        XCTAssertNil(store.track(forStartedAt: Self.startedAt))
    }

    func testAnEmptyRouteIsNotStored() {
        let store = LocalRouteStore()

        XCTAssertFalse(RouteHandoff.store(coordinates: [], startedAt: Self.startedAt, in: store))
        XCTAssertNil(store.track(forStartedAt: Self.startedAt))
    }

    func testADrawableRouteNeedsTwoPoints() {
        XCTAssertEqual(RouteHandoff.minimumDrawablePoints, 2)

        let store = LocalRouteStore()

        XCTAssertTrue(
            RouteHandoff.store(coordinates: route(2), startedAt: Self.startedAt, in: store)
        )
    }
}
