import XCTest
@testable import Drivy

/// The days of the Histórico list (S9) come from the `daily_scores` read the Hoy tab
/// already does, so the history screen costs no extra round trip.
final class TodayHistoryDaysTests: XCTestCase {

    /// 2023-11-14T22:13:20Z, i.e. 2023-11-14 in UTC.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func score(
        day: String,
        score: Int,
        distanceKm: Double = 10,
        drives: Int = 1
    ) -> DailyScoreRecord {
        DailyScoreRecord(day: day, score: score, distanceKm: distanceKm, drivesCount: drives)
    }

    private func load(_ fake: FakeTodayDataLoader) async throws -> TodaySnapshot {
        // The progress boundary is a stub: this file is about the `daily_scores`
        // read, and no test may reach the network.
        try await TodaySnapshotLoader(
            dataLoader: fake,
            progressLoader: StubProgressDataLoader(),
            calendar: utc
        )
        .load(userID: "user-1", now: Self.now)
    }

    func testDaysFollowTheStoredDailyScoresNewestFirst() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([
            score(day: "2023-11-14", score: 87, distanceKm: 12.34),
            score(day: "2023-11-13", score: 70, distanceKm: 8, drives: 2)
        ])

        let snapshot = try await load(fake)

        XCTAssertEqual(snapshot.days.map(\.dayKey), ["2023-11-14", "2023-11-13"])
        XCTAssertEqual(snapshot.days.map(\.score), [87, 70])
        XCTAssertEqual(snapshot.days.map(\.distanceKm), [12.34, 8])
        XCTAssertEqual(snapshot.days.map(\.drivesCount), [1, 2])
        XCTAssertEqual(snapshot.days.first?.date, utc.startOfDay(for: Self.now))
    }

    func testDaysWithoutDrivesAreNotHistory() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([
            score(day: "2023-11-14", score: 87),
            score(day: "2023-11-13", score: 0, distanceKm: 0, drives: 0)
        ])

        let snapshot = try await load(fake)

        XCTAssertEqual(snapshot.days.map(\.dayKey), ["2023-11-14"])
    }

    func testAnUnparseableDayKeyIsSkipped() async throws {
        let fake = FakeTodayDataLoader()
        fake.dailyScoresResult = .success([
            score(day: "no-es-una-fecha", score: 50),
            score(day: "2023-11-14", score: 87)
        ])

        let snapshot = try await load(fake)

        XCTAssertEqual(snapshot.days.map(\.dayKey), ["2023-11-14"])
    }

    func testAnEmptyDayHasNoHistory() async throws {
        let snapshot = try await load(FakeTodayDataLoader())

        XCTAssertTrue(snapshot.days.isEmpty)
    }
}
