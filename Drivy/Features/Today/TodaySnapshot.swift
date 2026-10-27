import Foundation

/// One day of the Histórico list (S9): a day of `public.daily_scores` that had at
/// least one drive.
struct HistoryDay: Equatable, Identifiable {

    /// `yyyy-MM-dd` day key of the row (S6).
    let dayKey: String

    /// Local start of that day, the value the gating rule takes.
    let date: Date

    let score: Int

    let distanceKm: Double

    let drivesCount: Int

    var id: String { dayKey }
}

/// Everything the Hoy screen and the share card need from S6, read once so both
/// show exactly the same numbers.
struct TodaySnapshot: Equatable {

    /// `yyyy-MM-dd` of the local day the snapshot describes.
    let dayKey: String

    /// Today's Driver Score; `nil` when there is no drive today.
    let score: Int?

    let distanceKm: Double

    let drivesCount: Int

    let streak: Streak

    /// Today's drives, newest first.
    let drives: [DriveHistoryRow]

    /// The days of the Histórico list, newest first. They come from the same
    /// `daily_scores` read as the streak, so the history screen costs no extra
    /// round trip (S9).
    let days: [HistoryDay]

    static let empty = TodaySnapshot(
        dayKey: "",
        score: nil,
        distanceKm: 0,
        drivesCount: 0,
        streak: .empty,
        drives: [],
        days: []
    )
}

/// The S6 read path in one place.
///
/// The daily score comes from `public.daily_scores`, which the upload path writes
/// when a drive finishes. When the row is missing (an upload that failed, or a day
/// recorded on another device that has not synced) the same distance-weighted rule
/// is applied to today's drives instead of inventing a number.
struct TodaySnapshotLoader {

    /// Days of `daily_scores` read to rebuild the streak. A year is far more than
    /// any streak the MVP will see.
    static let streakHistoryDays = 400

    let dataLoader: TodayDataLoading

    var calendar: Calendar = .current

    func load(userID: String, now: Date) async throws -> TodaySnapshot {
        let todayKey = DriveDay.key(for: now, calendar: calendar)
        let firstDayDate = calendar.date(byAdding: .day, value: -Self.streakHistoryDays, to: now) ?? now
        let firstDayKey = DriveDay.key(for: firstDayDate, calendar: calendar)

        let scores = try await dataLoader.dailyScores(
            userID: userID,
            from: firstDayKey,
            to: todayKey
        )
        let drives = try await dataLoader.drives(
            userID: userID,
            dayStart: DriveDay.start(of: now, calendar: calendar),
            dayEnd: DriveDay.end(of: now, calendar: calendar)
        )

        let drivingDays = Set(
            scores
                .filter { $0.drivesCount > 0 }
                .compactMap { DayKey.date(from: $0.day, calendar: calendar) }
        )
        let streak = StreakCalculator.streak(
            drivingDays: drivingDays,
            today: now,
            calendar: calendar
        )

        let storedToday = scores.first { $0.day == todayKey }
        let computedToday = DailyScoreCalculator.dailyScore(from: drives.map(\.aggregateInput))

        return TodaySnapshot(
            dayKey: todayKey,
            score: storedToday?.score ?? computedToday?.score,
            distanceKm: storedToday?.distanceKm ?? computedToday?.distanceKm ?? 0,
            drivesCount: storedToday?.drivesCount ?? computedToday?.drivesCount ?? 0,
            streak: streak,
            drives: drives,
            days: historyDays(from: scores)
        )
    }

    /// Days with at least one drive, in the order the rows were read (newest
    /// first). An empty `daily_scores` row is a day without driving, so it is not
    /// part of the history.
    private func historyDays(from scores: [DailyScoreRecord]) -> [HistoryDay] {
        scores
            .filter { $0.drivesCount > 0 }
            .compactMap { record in
                guard let date = DayKey.date(from: record.day, calendar: calendar) else {
                    return nil
                }
                return HistoryDay(
                    dayKey: record.day,
                    date: date,
                    score: record.score,
                    distanceKm: record.distanceKm,
                    drivesCount: record.drivesCount
                )
            }
    }
}
