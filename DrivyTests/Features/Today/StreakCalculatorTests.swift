import XCTest
@testable import Drivy

/// Streak v2 (S1), verbatim: "El día cuenta si conduces limpio (todos los trayectos
/// con score ≥ X) **o** si haces una lección de 1 minuto. Los días sin coche no
/// rompen nada."
///
/// The reference calendar is Europe/Madrid, the zone the days and the ISO weeks of
/// the product are counted in, and the dates are fixed so the rule is asserted
/// deterministically.
final class StreakCalculatorTests: XCTestCase {

    /// 2026-03-10, a Tuesday in the ISO week that starts on Monday 2026-03-09.
    private static let referenceDay = 10

    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }

    private func date(_ day: Int, month: Int = 3, hour: Int = 12) -> Date {
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour)
        return madrid.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private var today: Date {
        date(Self.referenceDay)
    }

    private func driving(_ score: Int, day: Int, month: Int = 3) -> StreakDrivingDay {
        StreakDrivingDay(day: date(day, month: month), score: score)
    }

    private func streak(
        driving drives: [StreakDrivingDay] = [],
        lessons: [Date] = [],
        repairs: [Date] = [],
        freezes: Int = FreemiumLimits.freeWeeklyFreezes,
        today reference: Date? = nil
    ) -> Streak {
        StreakCalculator.streak(
            drivingDays: drives,
            lessonDays: Set(lessons),
            repairedDays: Set(repairs),
            freezesPerWeek: freezes,
            today: reference ?? today,
            calendar: madrid
        )
    }

    // MARK: - Days that count

    func testCleanDrivingDayAddsADay() {
        let sut = streak(driving: [driving(90, day: 9), driving(75, day: 10)])

        XCTAssertEqual(sut.days, 2)
        XCTAssertTrue(sut.isTodayCounted)
    }

    /// S1: "score ≥ X" with X = 75, so 75 counts and 74 does not.
    func testTheThresholdIsInclusive() {
        let atThreshold = streak(driving: [driving(StreakCalculator.cleanDayThreshold, day: 10)])
        let belowThreshold = streak(
            driving: [driving(StreakCalculator.cleanDayThreshold - 1, day: 10)],
            freezes: 0
        )

        XCTAssertEqual(atThreshold.days, 1)
        XCTAssertTrue(atThreshold.isTodayCounted)
        XCTAssertEqual(belowThreshold.days, 0)
        XCTAssertFalse(belowThreshold.isTodayCounted)
    }

    func testLessonDayWithoutDrivingAddsADay() {
        let sut = streak(lessons: [date(9), date(10)])

        XCTAssertEqual(sut.days, 2)
        XCTAssertTrue(sut.isTodayCounted)
    }

    func testADayWithoutDrivingAndWithoutLessonIsNeutral() {
        // Clean on the 8th, nothing on the 9th, nothing today: nothing breaks and
        // nothing adds.
        let sut = streak(driving: [driving(90, day: 8)])

        XCTAssertEqual(sut.days, 1)
        XCTAssertFalse(sut.isTodayCounted)
        XCTAssertNil(sut.repairableDay)
    }

    /// S1: "Los días sin coche no rompen nada", however many of them there are.
    func testAWeekWithoutDrivingDoesNotBreakTheRun() {
        let sut = streak(driving: [driving(88, day: 1)])

        XCTAssertEqual(sut.days, 1)
    }

    // MARK: - Clean driving failures and freezes

    /// S1: a driving day below X spends one freeze of its week and the run survives
    /// without counting that day.
    func testADirtyDrivingDaySpendsAFreezeAndDoesNotCount() {
        let sut = streak(driving: [driving(60, day: 9), driving(90, day: 10)])

        XCTAssertEqual(sut.days, 1)
        XCTAssertEqual(sut.freezesUsedThisWeek, 1)
        XCTAssertEqual(sut.freezesLeftThisWeek, 0)
    }

    /// S1: without freezes left the run breaks, on the day of the failure.
    func testASecondDirtyDayOfTheSameWeekBreaksTheRun() {
        // Week of 2-8 March: the 2nd is the frozen failure and the 3rd, with no
        // freeze left, breaks the run. Only the 4th onward counts.
        let sut = streak(driving: [
            driving(60, day: 2),
            driving(60, day: 3),
            driving(90, day: 4),
            driving(90, day: 10)
        ])

        XCTAssertEqual(sut.days, 2)
        XCTAssertNil(sut.repairableDay)
    }

    /// S1: "no se acumulan entre semanas". A failure last week spends last week's
    /// freeze, and this week starts with a fresh one.
    func testFreezesAreNotCarriedOverBetweenWeeks() {
        let sut = streak(driving: [
            driving(60, day: 2),
            driving(60, day: 9),
            driving(90, day: 10)
        ])

        XCTAssertEqual(sut.days, 1)
        XCTAssertEqual(sut.freezesUsedThisWeek, 1)
        XCTAssertEqual(sut.freezesLeftThisWeek, 0)
    }

    /// S8: Premium gets three freezes per week, so three failures of the same week
    /// are covered.
    func testPremiumAllowanceCoversThreeFailuresOfTheSameWeek() {
        let drives = [
            driving(90, day: 1),
            driving(60, day: 2),
            driving(60, day: 3),
            driving(60, day: 4),
            driving(90, day: 5),
            driving(90, day: 10)
        ]

        let premium = streak(driving: drives, freezes: FreemiumLimits.premiumWeeklyFreezes)
        let twoFreezes = streak(driving: drives, freezes: 2)

        // 1, 5 and 10 March count; the three failures of 2-4 March are frozen.
        XCTAssertEqual(premium.days, 3)
        XCTAssertEqual(premium.freezesLeftThisWeek, FreemiumLimits.premiumWeeklyFreezes)
        // With two freezes the third failure (the 4th) breaks the run, so the 1st
        // falls out of it.
        XCTAssertEqual(twoFreezes.days, 2)
    }

    /// S1: a lesson does not rescue a dirty driving day, otherwise driving badly
    /// would be free.
    func testALessonDoesNotRescueADirtyDrivingDay() {
        let sut = streak(
            driving: [driving(90, day: 8), driving(60, day: 9)],
            lessons: [date(9), date(10)],
            freezes: 0
        )

        // The run stops at the 9th: only today's lesson counts.
        XCTAssertEqual(sut.days, 1)
        XCTAssertTrue(sut.isTodayCounted)
    }

    /// S1: today never breaks the run while it is still today.
    func testTodayIsNeverABreak() {
        let sut = streak(
            driving: [driving(90, day: 8), driving(60, day: 9), driving(60, day: 10)]
        )

        // The failure of the 9th spends the freeze, and the one of today, with no
        // freeze left, would break the run: it is only forgiven because today is
        // not over.
        XCTAssertEqual(sut.days, 1)
        XCTAssertFalse(sut.isTodayCounted)
        XCTAssertNil(sut.repairableDay)
    }

    // MARK: - S8 repairs

    /// S8: a repaired day is forgiven, so it joins the run instead of breaking it,
    /// and it does not spend a freeze.
    func testARepairedDayIsForgivenAndCounts() {
        let sut = streak(
            driving: [driving(90, day: 8), driving(60, day: 9), driving(90, day: 10)],
            repairs: [date(9)],
            freezes: 0
        )

        XCTAssertEqual(sut.days, 3)
        XCTAssertEqual(sut.freezesUsedThisWeek, 0)
    }

    /// S8: the break can be repaired during the 48 h that follow the end of the
    /// broken day.
    func testTheBrokenDayOfYesterdayIsRepairable() {
        let sut = streak(driving: [driving(90, day: 8), driving(60, day: 9), driving(60, day: 10)])

        // The 9th spends the freeze and today (never a break) would be the second
        // failure: nothing to repair yet.
        XCTAssertNil(sut.repairableDay)

        let broken = streak(driving: [driving(60, day: 9)], freezes: 0)
        XCTAssertEqual(broken.days, 0)
        XCTAssertEqual(broken.repairableDay, madrid.startOfDay(for: date(9)))
    }

    /// S8: a break older than the window is not offered.
    func testABreakOutsideTheWindowIsNotRepairable() {
        let sut = streak(driving: [driving(60, day: 6)], freezes: 0)

        XCTAssertNil(sut.repairableDay)
    }

    // MARK: - Empty data

    func testNoDataMeansNoStreakButKeepsTheWeeklyAllowance() {
        let sut = streak(freezes: FreemiumLimits.premiumWeeklyFreezes)

        XCTAssertEqual(sut.days, 0)
        XCTAssertFalse(sut.isTodayCounted)
        XCTAssertNil(sut.repairableDay)
        XCTAssertEqual(sut.freezesUsedThisWeek, 0)
        XCTAssertEqual(sut.freezesLeftThisWeek, FreemiumLimits.premiumWeeklyFreezes)
    }

    func testStreakEmptyIsTheUnloadedValue() {
        XCTAssertEqual(Streak.empty.days, 0)
        XCTAssertEqual(Streak.empty.freezesLeftThisWeek, 0)
        XCTAssertFalse(Streak.empty.isTodayCounted)
        XCTAssertNil(Streak.empty.repairableDay)
    }

    // MARK: - Copy shown by the racha card

    func testHeadlineCountsTheDays() {
        XCTAssertEqual(streak().headline, "Sin racha")
        XCTAssertEqual(streak(driving: [driving(90, day: 10)]).headline, "1 día de racha")
        XCTAssertEqual(
            streak(driving: [driving(90, day: 9), driving(90, day: 10)]).headline,
            "2 días de racha"
        )
    }

    /// S7: the copy never invites the user to drive, so the lesson is the action it
    /// names first.
    func testDetailAsksForTheLessonAndNotForADrive() {
        XCTAssertEqual(
            streak(driving: [driving(90, day: 9)]).detail(todayHasDirtyDriving: false),
            "Haz la lección de hoy (1 minuto) para sumar el día. No hace falta conducir."
        )
        XCTAssertEqual(
            streak().detail(todayHasDirtyDriving: false),
            "Haz la lección de hoy para empezar la racha. Los días sin coche no la rompen."
        )
        XCTAssertEqual(
            streak(lessons: [date(10)]).detail(todayHasDirtyDriving: false),
            "Hoy ya cuenta para tu racha."
        )
    }

    /// S1: "Una lección ese mismo día no lo rescata". On a day whose driving is
    /// already below the threshold the card must not promise the day, because the
    /// lesson cannot give it (B5).
    func testDetailOnADirtyDrivingDayDoesNotPromiseTheDay() {
        let sut = streak(driving: [driving(90, day: 9), driving(60, day: 10)])

        XCTAssertFalse(sut.isTodayCounted)
        XCTAssertEqual(
            sut.detail(todayHasDirtyDriving: true),
            "Hoy ya hay trayectos con nota por debajo de 75: la lección no suma el día. "
                + "Mañana cuenta si conduces con cuidado o si haces la lección."
        )
    }

    /// S1/B5: the lesson of a dirty day does not change the copy, because it does
    /// not rescue the day: the message is the same before and after doing it.
    func testTheLessonOfADirtyDayDoesNotChangeTheMessage() {
        let before = streak(driving: [driving(60, day: 10)])
        let after = streak(driving: [driving(60, day: 10)], lessons: [date(10)])

        XCTAssertFalse(before.isTodayCounted)
        XCTAssertFalse(after.isTodayCounted)
        XCTAssertEqual(
            before.detail(todayHasDirtyDriving: true),
            after.detail(todayHasDirtyDriving: true)
        )
        XCTAssertEqual(
            Streak.lessonMessage(hasLessonToday: false, todayHasDirtyDriving: true),
            Streak.lessonMessage(hasLessonToday: true, todayHasDirtyDriving: true)
        )
    }

    /// S1/B5: the state the copy is branched on. A day without driving is never
    /// dirty ("los días sin coche no rompen nada"), and the threshold is the same one
    /// the run uses.
    func testTodayIsDirtyOnlyWithDrivingBelowTheThreshold() {
        XCTAssertTrue(Streak.hasDirtyDrivingToday(dayScore: 60, drivesCount: 1))
        XCTAssertFalse(
            Streak.hasDirtyDrivingToday(
                dayScore: StreakCalculator.cleanDayThreshold,
                drivesCount: 1
            )
        )
        XCTAssertFalse(Streak.hasDirtyDrivingToday(dayScore: 90, drivesCount: 2))
        XCTAssertFalse(Streak.hasDirtyDrivingToday(dayScore: nil, drivesCount: 0))
        XCTAssertFalse(Streak.hasDirtyDrivingToday(dayScore: 60, drivesCount: 0))
    }

    /// S1/S2/B5: the lesson card promises the day only when the rule can give it.
    func testLessonCardCopyFollowsTheDirtyDayRule() {
        XCTAssertEqual(
            Streak.lessonMessage(hasLessonToday: false, todayHasDirtyDriving: false),
            "Un minuto de teoría. Hacerla ya hace que el día cuente para la racha, aunque no cojas el coche."
        )
        XCTAssertEqual(
            Streak.lessonMessage(hasLessonToday: true, todayHasDirtyDriving: false),
            "Ya has hecho la lección de hoy: cuenta para tu racha."
        )
        XCTAssertEqual(
            Streak.lessonMessage(hasLessonToday: false, todayHasDirtyDriving: true),
            Streak.notRescuedTodayMessage
        )
        XCTAssertEqual(
            Streak.lessonMessage(hasLessonToday: true, todayHasDirtyDriving: true),
            Streak.notRescuedTodayMessage
        )
    }

    /// Safety principle: the copy on a dirty day says the lesson does not rescue the
    /// day and never asks for more driving (S7).
    func testTheDirtyDayCopyNeverInvitesToDriveMore() {
        let copies = [
            streak(driving: [driving(60, day: 10)]).detail(todayHasDirtyDriving: true),
            Streak.lessonMessage(hasLessonToday: false, todayHasDirtyDriving: true)
        ]

        for copy in copies {
            XCTAssertTrue(copy.contains("Mañana cuenta"))
            XCTAssertFalse(copy.contains("más"))
        }
    }

    func testFreezeTextFollowsTheWeeklyAllowance() {
        XCTAssertEqual(
            streak(freezes: 3).freezeText,
            "Te quedan 3 hielos esta semana."
        )
        XCTAssertEqual(
            streak(driving: [driving(60, day: 9)], freezes: 3).freezeText,
            "Te quedan 2 hielos esta semana."
        )
        XCTAssertEqual(
            streak(driving: [driving(60, day: 9)]).freezeText,
            "Sin hielos esta semana: un día con nota por debajo de 75 rompería la racha."
        )
    }
}
