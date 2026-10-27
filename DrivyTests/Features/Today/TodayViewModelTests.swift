import XCTest
@testable import Drivy

/// State of the Hoy tab (S6), exercised with a fake Supabase boundary.
@MainActor
final class TodayViewModelTests: XCTestCase {

    /// 2023-11-14T22:13:20Z, i.e. 2023-11-14 in UTC.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userID = "user-1"

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func makeSUT() -> (sut: TodayViewModel, fake: FakeTodayDataLoader) {
        let fake = FakeTodayDataLoader()
        let sut = TodayViewModel(dataLoader: fake, calendar: utc, now: { Self.now })
        return (sut, fake)
    }

    private func drive(score: Int, distanceKm: Double) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "row-\(score)",
            startedAt: Self.now,
            endedAt: Self.now.addingTimeInterval(600),
            distanceKm: distanceKm,
            durationSeconds: 600,
            score: score,
            harshBrakes: 1,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
    }

    func testLoadPublishesTheDayAndTheStreak() async {
        let (sut, fake) = makeSUT()
        fake.dailyScoresResult = .success([
            DailyScoreRecord(day: "2023-11-14", score: 87, distanceKm: 12.34, drivesCount: 1),
            DailyScoreRecord(day: "2023-11-13", score: 70, distanceKm: 8, drivesCount: 2)
        ])
        fake.drivesResult = .success([drive(score: 87, distanceKm: 12.34)])

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.snapshot.score, 87)
        XCTAssertEqual(sut.snapshot.distanceKm, 12.34)
        XCTAssertEqual(sut.snapshot.drivesCount, 1)
        XCTAssertEqual(sut.snapshot.streak.days, 2)
        XCTAssertEqual(sut.snapshot.drives.count, 1)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadUsesTheSignedInUserID() async {
        let (sut, fake) = makeSUT()

        await sut.load(userID: Self.userID)

        XCTAssertEqual(fake.dailyScoresCalls.last?.userID, Self.userID)
        XCTAssertEqual(fake.drivesCalls.last?.userID, Self.userID)
    }

    func testLoadFailureShowsTheSpanishMessage() async {
        let (sut, fake) = makeSUT()
        fake.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.errorMessage, TodayViewModel.loadFailureMessage)
        XCTAssertEqual(sut.snapshot, .empty)
        XCTAssertFalse(sut.isLoading)
    }

    /// A failed refresh must not blank the day the user is already looking at.
    func testFailedRefreshKeepsThePreviousDay() async {
        let (sut, fake) = makeSUT()
        fake.dailyScoresResult = .success([
            DailyScoreRecord(day: "2023-11-14", score: 87, distanceKm: 12.34, drivesCount: 1)
        ])
        await sut.load(userID: Self.userID)

        fake.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)
        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.snapshot.score, 87)
        XCTAssertEqual(sut.errorMessage, TodayViewModel.loadFailureMessage)
    }

    func testReloadClearsThePreviousError() async {
        let (sut, fake) = makeSUT()
        fake.dailyScoresResult = .failure(FakeTodayDataLoader.FakeError.network)
        await sut.load(userID: Self.userID)
        XCTAssertNotNil(sut.errorMessage)

        fake.dailyScoresResult = .success([])
        await sut.load(userID: Self.userID)

        XCTAssertNil(sut.errorMessage)
    }
}
