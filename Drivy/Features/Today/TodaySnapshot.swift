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

/// Everything the Hoy screen and the share card need from the Duolingo loop (S1,
/// S4, S6), read once so both show exactly the same numbers.
struct TodaySnapshot: Equatable {

    /// `yyyy-MM-dd` of the local day the snapshot describes.
    let dayKey: String

    /// Today's Driver Score; `nil` when there is no drive today.
    let score: Int?

    let distanceKm: Double

    let drivesCount: Int

    /// Streak v2 of the run that ends today (S1).
    let streak: Streak

    /// Today's drives, newest first.
    let drives: [DriveHistoryRow]

    /// The days of the Histórico list, newest first. They come from the same
    /// `daily_scores` read as the streak, so the history screen costs no extra
    /// round trip (S9).
    let days: [HistoryDay]

    /// Lifetime and current-week XP (S4); `nil` when the read failed, so the card
    /// hides instead of showing a fake 0.
    let xp: XPTotals?

    /// The three quests of the day (S6), in board order.
    let quests: [DailyQuestProgress]

    /// Quests satisfied today that are not recorded yet. The owner of the write
    /// path (`TodayViewModel`) stores them through `ProgressDataLoading`, so the
    /// read path here stays free of side effects and can be reused by the share
    /// card.
    let pendingQuestIDs: [String]

    /// True when today's lesson is already recorded (S2).
    let hasLessonToday: Bool

    /// Creation date of the last streak repair (S8); `nil` when there is none.
    /// The repair gate turns it into the 30-day cooldown.
    let lastStreakRepairAt: Date?

    static let empty = TodaySnapshot(
        dayKey: "",
        score: nil,
        distanceKm: 0,
        drivesCount: 0,
        streak: .empty,
        drives: [],
        days: [],
        xp: nil,
        quests: [],
        pendingQuestIDs: [],
        hasLessonToday: false,
        lastStreakRepairAt: nil
    )
}

/// The read path of the Duolingo loop in one place.
///
/// The daily score comes from `public.daily_scores`, which the upload path writes
/// when a drive finishes. When the row is missing (an upload that failed, or a day
/// recorded on another device that has not synced) the same distance-weighted rule
/// is applied to today's drives instead of inventing a number, and the streak uses
/// that value too so the score card and the streak cannot disagree about today.
///
/// Two boundaries are used on purpose: the Hoy tables go through
/// `TodayDataLoading`, and everything of the loop (lessons, repairs, XP, quests)
/// through the shared `ProgressDataLoading`, so no query of that layer is
/// re-implemented here.
struct TodaySnapshotLoader {

    /// Days of `daily_scores` read to rebuild the streak. A year is far more than
    /// any streak the MVP will see.
    static let streakHistoryDays = 400

    let dataLoader: TodayDataLoading

    let progressLoader: ProgressDataLoading

    let calendar: Calendar

    init(
        dataLoader: TodayDataLoading,
        progressLoader: ProgressDataLoading = SupabaseProgressRepository(),
        calendar: Calendar = .current
    ) {
        self.dataLoader = dataLoader
        self.progressLoader = progressLoader
        self.calendar = calendar
    }

    /// - Parameter plan: plan in force, which decides the weekly freeze allowance
    ///   of S1/S8. `nil` (plan still unknown) reads the free allowance, which is
    ///   the conservative one: it never shows more freezes than the user has.
    func load(userID: String, now: Date, plan: FreemiumPlan? = nil) async throws -> TodaySnapshot {
        let todayKey = DriveDay.key(for: now, calendar: calendar)
        let dayStart = DriveDay.start(of: now, calendar: calendar)
        let firstDayDate = calendar.date(byAdding: .day, value: -Self.streakHistoryDays, to: now) ?? now
        let firstDayKey = DriveDay.key(for: firstDayDate, calendar: calendar)

        let scores = try await dataLoader.dailyScores(
            userID: userID,
            from: firstDayKey,
            to: todayKey
        )
        let drives = try await dataLoader.drives(
            userID: userID,
            dayStart: dayStart,
            dayEnd: DriveDay.end(of: now, calendar: calendar)
        )
        // Lessons and repairs feed the streak rule, so their failure is a failure
        // of the screen: an incomplete streak would be a wrong streak.
        let lessonDayKeys = try await progressLoader.lessonDays(from: firstDayKey, to: todayKey)
        let repairs = try await progressLoader.streakRepairs()

        // XP and quests are extra information: a failed read hides or degrades one
        // section instead of blanking the day (same stance as the share card with
        // the league position).
        let xp = try? await progressLoader.xp(
            weekStart: WeekBounds.mondayKey(for: now, calendar: calendar)
        )
        let storedQuestIDs = Set((try? await progressLoader.completedQuests(day: todayKey)) ?? [])

        let storedToday = scores.first { $0.day == todayKey }
        let computedToday = DailyScoreCalculator.dailyScore(from: drives.map(\.aggregateInput))

        let lessonDays = Set(lessonDayKeys.compactMap { DayKey.date(from: $0, calendar: calendar) })
        let repairedDays = Set(repairs.compactMap { DayKey.date(from: $0.day, calendar: calendar) })

        var drivingDays = scores
            .filter { $0.drivesCount > 0 }
            .compactMap { record -> StreakDrivingDay? in
                guard let date = DayKey.date(from: record.day, calendar: calendar) else { return nil }
                return StreakDrivingDay(day: date, score: record.score)
            }
        // Today's row may not be written yet: count the day the score card already
        // shows, so the streak and the score agree.
        if storedToday == nil, let computedToday = computedToday {
            drivingDays.append(StreakDrivingDay(day: dayStart, score: computedToday.score))
        }

        let streak = StreakCalculator.streak(
            drivingDays: drivingDays,
            lessonDays: lessonDays,
            repairedDays: repairedDays,
            freezesPerWeek: FreemiumLimits.weeklyFreezes(for: plan ?? .free),
            today: now,
            calendar: calendar
        )

        let hasLessonToday = lessonDays.contains(dayStart)
        let quests = questProgress(
            userID: userID,
            dayKey: todayKey,
            drives: drives,
            isLessonDone: hasLessonToday,
            storedQuestIDs: storedQuestIDs
        )

        return TodaySnapshot(
            dayKey: todayKey,
            score: storedToday?.score ?? computedToday?.score,
            distanceKm: storedToday?.distanceKm ?? computedToday?.distanceKm ?? 0,
            drivesCount: storedToday?.drivesCount ?? computedToday?.drivesCount ?? 0,
            streak: streak,
            drives: drives,
            days: historyDays(from: scores),
            xp: xp,
            quests: quests,
            pendingQuestIDs: quests
                .filter { $0.isCompleted && !storedQuestIDs.contains($0.quest.id) }
                .map(\.quest.id),
            hasLessonToday: hasLessonToday,
            lastStreakRepairAt: repairs.first?.createdAt
        )
    }

    /// The board of the day plus today's evaluation of each quest (S6).
    private func questProgress(
        userID: String,
        dayKey: String,
        drives: [DriveHistoryRow],
        isLessonDone: Bool,
        storedQuestIDs: Set<String>
    ) -> [DailyQuestProgress] {
        let context = QuestDayContext(drives: drives, isLessonDone: isLessonDone)

        return DailyQuestBoard.quests(for: userID, dayKey: dayKey).map { quest in
            // A stored completion is a completion: the row exists because the rule
            // was satisfied, and the drives of that day may since have been
            // rewritten by a later upload.
            DailyQuestProgress(
                quest: quest,
                isCompleted: storedQuestIDs.contains(quest.id)
                    || QuestEvaluator.isSatisfied(quest, in: context)
            )
        }
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
