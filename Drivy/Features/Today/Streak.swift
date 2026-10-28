import Foundation

/// One day with driving, as the S1 rule needs it.
struct StreakDrivingDay: Equatable {

    /// Local start of the day.
    let day: Date

    /// Driver Score of that day: the distance-weighted daily score that
    /// `public.daily_scores` stores (S1, S6).
    let score: Int
}

/// Streak v2 (S1): the run of days the user drove cleanly **or** did a lesson.
///
/// S1 replaces the old "consecutive days with ≥ 1 drive" rule (S6 of the MVP)
/// because that one rewarded driving more. Here the day counts for the quality of
/// the driving, and a day without a car does not break anything.
struct Streak: Equatable {

    /// Days of the current run: clean driving days, driving days forgiven by a
    /// repair and lesson days. A day that only survives on a freeze does not add
    /// to the count.
    let days: Int

    /// Freezes ("hielos") the ISO week of today already spent on driving days
    /// below `StreakCalculator.cleanDayThreshold`.
    let freezesUsedThisWeek: Int

    /// Freezes the plan still has this week. They are not carried over, so this
    /// is always between 0 and the plan allowance.
    let freezesLeftThisWeek: Int

    /// True when today already adds a day: a clean drive or a lesson.
    let isTodayCounted: Bool

    /// The day that broke the run, when the break happened inside the S8 repair
    /// window. The card offers the premium repair only for this day.
    let repairableDay: Date?

    static let empty = Streak(
        days: 0,
        freezesUsedThisWeek: 0,
        freezesLeftThisWeek: 0,
        isTodayCounted: false,
        repairableDay: nil
    )
}

/// The S1 rule, as a pure and deterministic function of the stored days.
///
/// S1, verbatim: "El día cuenta si conduces limpio (todos los trayectos con score
/// ≥ X) **o** si haces una lección de 1 minuto. Los días sin coche no rompen
/// nada." The approved reading, day by day:
///
/// - a driving day with a daily score of at least `cleanDayThreshold` adds a day;
/// - a day without driving that has a lesson adds a day (a lesson on a driving
///   day does not add twice);
/// - a day without driving and without a lesson is neutral: it neither adds nor
///   breaks, which is the "los días sin coche no rompen nada" part;
/// - a driving day below the threshold spends one freeze of **its** ISO week and
///   the run survives without adding that day; without freezes left it breaks the
///   run, unless that day was forgiven with a premium repair (S8). A lesson on
///   that same day does not rescue it: otherwise driving badly would be free;
/// - today never breaks the run while it is still today: the user still has the
///   rest of the day to drive cleanly or to do the lesson.
///
/// Nothing is persisted: the freezes and the repairs are reapplied on every read,
/// so two devices always compute the same streak from the same rows.
enum StreakCalculator {

    /// S1: daily Driver Score from which a driving day counts ("score ≥ X", X =
    /// 75 over the distance-weighted daily average).
    static let cleanDayThreshold = 75

    /// Streak state of the run that ends today.
    ///
    /// - Parameters:
    ///   - drivingDays: days with driving and their daily score.
    ///   - lessonDays: days with a completed theory lesson.
    ///   - repairedDays: days forgiven with the premium repair (S8).
    ///   - freezesPerWeek: plan allowance of S1/S8 (Free 1, Premium 3).
    ///   - today: reference date; its time of day is what decides whether the 48 h
    ///     repair window is still open.
    ///   - calendar: day and ISO-week grouping, injected so tests pin it.
    static func streak(
        drivingDays: [StreakDrivingDay],
        lessonDays: Set<Date>,
        repairedDays: Set<Date>,
        freezesPerWeek: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> Streak {
        let todayStart = calendar.startOfDay(for: today)
        let scores = scoresByDay(from: drivingDays, calendar: calendar)
        let lessons = Set(lessonDays.map { calendar.startOfDay(for: $0) })
        let repairs = Set(repairedDays.map { calendar.startOfDay(for: $0) })
        let allowance = max(0, freezesPerWeek)

        guard let earliestDay = ([Date](scores.keys) + [Date](lessons) + [Date](repairs)).min() else {
            // No data at all: the plan allowance is still shown, because the card
            // tells the user how many freezes this week has.
            return Streak(
                days: 0,
                freezesUsedThisWeek: 0,
                freezesLeftThisWeek: allowance,
                isTodayCounted: false,
                repairableDay: nil
            )
        }

        // First pass, oldest day first: this is the chronological order in which
        // the freezes are spent, which is what makes "the first failure of the
        // week is the one the freeze covers" true.
        var outcomes: [Date: DayOutcome] = [:]
        var freezesUsedByWeek: [Date: Int] = [:]

        var cursor = earliestDay
        while cursor <= todayStart {
            let weekStart = WeekBounds.monday(for: cursor, calendar: calendar)

            if let score = scores[cursor] {
                if score >= cleanDayThreshold {
                    outcomes[cursor] = .counted
                } else if repairs.contains(cursor) {
                    // S8: the repair forgives the day. It joins the run without
                    // spending a freeze, and it counts like the day it was.
                    outcomes[cursor] = .counted
                } else {
                    let used = freezesUsedByWeek[weekStart] ?? 0
                    if used < allowance {
                        freezesUsedByWeek[weekStart] = used + 1
                        outcomes[cursor] = .frozen
                    } else {
                        outcomes[cursor] = .broken
                    }
                }
            } else if lessons.contains(cursor) {
                outcomes[cursor] = .counted
            } else {
                outcomes[cursor] = .neutral
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // Second pass, newest day first: the run ends at the first day that
        // actually broke it.
        var days = 0
        var brokenDay: Date?

        cursor = todayStart
        while cursor >= earliestDay {
            let outcome = outcomes[cursor] ?? .neutral

            if outcome == .broken && cursor != todayStart {
                brokenDay = cursor
                break
            }
            if outcome == .counted {
                days += 1
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let thisWeek = WeekBounds.monday(for: todayStart, calendar: calendar)
        let usedThisWeek = freezesUsedByWeek[thisWeek] ?? 0
        let repairableDay = brokenDay.flatMap { day in
            isInsideRepairWindow(day, now: today, calendar: calendar) ? day : nil
        }

        return Streak(
            days: days,
            freezesUsedThisWeek: usedThisWeek,
            freezesLeftThisWeek: max(0, allowance - usedThisWeek),
            isTodayCounted: outcomes[todayStart] == DayOutcome.counted,
            repairableDay: repairableDay
        )
    }

    /// S8: a break can be repaired during the 48 h that follow the end of the day
    /// that broke the run. The break is only committed when that day ends, hence
    /// the day-after boundary.
    static func isInsideRepairWindow(_ day: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
            let deadline = calendar.date(
                byAdding: .hour,
                value: FreemiumLimits.streakRepairWindowHours,
                to: dayEnd
            )
        else {
            return false
        }
        return now < deadline
    }

    // MARK: - Internals

    /// State of one day of the window once the freezes of its week are known.
    private enum DayOutcome: Equatable {
        /// Adds a day to the run.
        case counted
        /// Driving below the threshold, covered by a freeze: keeps the run alive.
        case frozen
        /// Nothing happened: no driving, no lesson.
        case neutral
        /// Driving below the threshold without a freeze: the run stops here.
        case broken
    }

    /// One score per day. `daily_scores` has one row per day (primary key), but
    /// keeping the best score makes the rule deterministic if two ever arrive.
    private static func scoresByDay(
        from drivingDays: [StreakDrivingDay],
        calendar: Calendar
    ) -> [Date: Int] {
        var scores: [Date: Int] = [:]
        for entry in drivingDays {
            let day = calendar.startOfDay(for: entry.day)
            scores[day] = max(scores[day] ?? entry.score, entry.score)
        }
        return scores
    }
}

// MARK: - Copy of the racha card

extension Streak {

    /// Headline of the card. Spanish, because it is user-facing copy.
    var headline: String {
        switch days {
        case 0:
            return "Sin racha"
        case 1:
            return "1 día de racha"
        default:
            return "\(days) días de racha"
        }
    }

    /// Second line: what today needs to add a day.
    ///
    /// It always names the lesson first: S7 forbids inviting the user to drive, so
    /// the copy never asks for a drive.
    ///
    /// - Parameter todayHasDirtyDriving: today already has driving and its daily
    ///   score is below `StreakCalculator.cleanDayThreshold`. S1 is explicit that a
    ///   lesson that same day does not rescue the day ("Una lección ese mismo día no
    ///   lo rescata"), so promising the day there would be a lie the user pays a
    ///   minute for (B5).
    func detail(todayHasDirtyDriving: Bool) -> String {
        if isTodayCounted {
            return "Hoy ya cuenta para tu racha."
        }
        if todayHasDirtyDriving {
            return Self.notRescuedTodayMessage
        }
        if days > 0 {
            return "Haz la lección de hoy (1 minuto) para sumar el día. No hace falta conducir."
        }
        return "Haz la lección de hoy para empezar la racha. Los días sin coche no la rompen."
    }

    /// Copy of the lesson card of the Hoy tab (S1, S2).
    ///
    /// Same rule as `detail(todayHasDirtyDriving:)`: on a day whose driving is
    /// already below the clean-day threshold the lesson cannot make the day count,
    /// so the card states the rule instead of promising the day (B5). The button
    /// stays available: the lesson still pays its XP (S4), it just does not rescue
    /// this day.
    static func lessonMessage(hasLessonToday: Bool, todayHasDirtyDriving: Bool) -> String {
        if todayHasDirtyDriving {
            return notRescuedTodayMessage
        }
        if hasLessonToday {
            return "Ya has hecho la lección de hoy: cuenta para tu racha."
        }
        return "Un minuto de teoría. Hacerla ya hace que el día cuente para la racha, aunque no cojas el coche."
    }

    /// S1: today already has driving and its daily score is below the clean-day
    /// threshold, which is the one state in which the day is already ruled out and
    /// "Una lección ese mismo día no lo rescata". The copy of the racha card and of
    /// the lesson card is branched on it, so neither promises a day the rule refuses
    /// (B5).
    ///
    /// It is the same input the calculator received for today: the stored
    /// `daily_scores` row, or today's drives aggregated when that row is not written
    /// yet. A day without driving is never dirty (S1: "los días sin coche no rompen
    /// nada"), hence the drive count.
    static func hasDirtyDrivingToday(dayScore: Int?, drivesCount: Int) -> Bool {
        guard drivesCount > 0, let dayScore else { return false }
        return dayScore < StreakCalculator.cleanDayThreshold
    }

    /// S1: what the cards say on a day whose driving already rules the day out.
    ///
    /// It repeats the rule the calculator applies and what tomorrow needs, and it
    /// never invites the user to drive: it names a clean drive and the lesson as the
    /// two equal ways the next day counts, exactly as S1 defines them.
    static let notRescuedTodayMessage = "Hoy ya hay trayectos con nota por debajo de 75: la lección no suma el día. "
        + "Mañana cuenta si conduces con cuidado o si haces la lección."

    /// S1/S8: the freezes of the week, in one line.
    var freezeText: String {
        switch freezesLeftThisWeek {
        case 0:
            return "Sin hielos esta semana: un día con nota por debajo de 75 rompería la racha."
        case 1:
            return "Te queda 1 hielo esta semana."
        default:
            return "Te quedan \(freezesLeftThisWeek) hielos esta semana."
        }
    }
}
