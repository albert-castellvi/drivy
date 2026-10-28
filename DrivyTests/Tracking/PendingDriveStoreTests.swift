import XCTest
@testable import Drivy

/// D4: the pending store keeps a failed upload's drive across launches, one
/// entry per drive id, with atomic writes and injectable directory/file
/// manager. These tests re-instantiate the store on the same directory to prove
/// the entries survive the object, not just the instance.
final class PendingDriveStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingDriveStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeStore() -> PendingDriveStore {
        PendingDriveStore(directory: directory)
    }

    private func makeRecord(startedAt: Date, score: Int = 88) -> DriveRecord {
        DriveRecord(
            score: DriveScore(
                score: score,
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

    // MARK: - Round trip

    func testEntriesSurviveANewStoreInstanceOnTheSameDirectory() throws {
        let record = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))
        let entry = PendingDriveUpload(record: record, sessionUserID: "user-a")
        try makeStore().add(entry)

        // A new object over the same directory reads what the first one wrote.
        let reloaded = makeStore()

        XCTAssertEqual(reloaded.all(), [entry])
    }

    func testRoundTripKeepsTheEventsWithTheirCoordinates() throws {
        // S2: the record carries where each counted event happened; the store
        // must round-trip it (the events stay on the phone, S10/S12).
        let record = DriveRecord(
            score: DriveScore(
                score: 88,
                distanceKm: 1.0,
                durationSeconds: 100,
                harshBrakes: 1,
                harshAccelerations: 0,
                phoneUseEvents: 0,
                speedingEvents: 0,
                connectedMode: false
            ),
            startedAt: Date(timeIntervalSince1970: 1_000),
            events: [
                DriveEvent(
                    kind: .harshBrake,
                    timestamp: 50,
                    coordinate: DriveCoordinate(latitude: 41.3874, longitude: 2.1686)
                ),
                DriveEvent(kind: .phoneUse),
            ]
        )
        let entry = PendingDriveUpload(record: record, sessionUserID: "user-a")
        try makeStore().add(entry)

        XCTAssertEqual(makeStore().all(), [entry])
    }

    func testAllReturnsTheEntriesOldestDriveFirst() throws {
        let store = makeStore()
        let oldest = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))
        let middle = makeRecord(startedAt: Date(timeIntervalSince1970: 2_000))
        let newest = makeRecord(startedAt: Date(timeIntervalSince1970: 3_000))

        // Added newest first on purpose: the read order must not depend on it.
        try store.add(PendingDriveUpload(record: newest, sessionUserID: "user-a"))
        try store.add(PendingDriveUpload(record: middle, sessionUserID: "user-a"))
        try store.add(PendingDriveUpload(record: oldest, sessionUserID: "user-a"))

        XCTAssertEqual(makeStore().all().map(\.record.id), [oldest.id, middle.id, newest.id])
    }

    // MARK: - One entry per drive id

    func testAddingTheSameDriveIDReplacesItsEntry() throws {
        let store = makeStore()
        let record = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))

        try store.add(PendingDriveUpload(record: record, sessionUserID: "user-a"))
        try store.add(PendingDriveUpload(record: record, sessionUserID: "user-b"))

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.all().count, 1)
        XCTAssertEqual(reloaded.all().first?.sessionUserID, "user-b")
    }

    // MARK: - Removal

    func testRemoveDeletesOnlyTheGivenDriveAcrossInstances() throws {
        let store = makeStore()
        let first = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))
        let second = makeRecord(startedAt: Date(timeIntervalSince1970: 2_000))
        try store.add(PendingDriveUpload(record: first, sessionUserID: "user-a"))
        try store.add(PendingDriveUpload(record: second, sessionUserID: "user-a"))

        try makeStore().remove(id: first.id)

        let reloaded = makeStore()
        XCTAssertFalse(reloaded.contains(id: first.id))
        XCTAssertEqual(reloaded.all().map(\.record.id), [second.id])
    }

    func testRemoveOfAnUnknownIDLeavesTheStoreUntouched() throws {
        let store = makeStore()
        let record = makeRecord(startedAt: Date(timeIntervalSince1970: 1_000))
        try store.add(PendingDriveUpload(record: record, sessionUserID: "user-a"))

        try makeStore().remove(id: UUID())

        XCTAssertEqual(makeStore().all().count, 1)
    }
}
