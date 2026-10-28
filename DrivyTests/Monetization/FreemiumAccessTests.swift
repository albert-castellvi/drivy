import XCTest
@testable import Drivy

/// Gating predicates of S9, exercised as pure value rules.
///
/// S9: "7 días de histórico completo gratis; después, Free = solo último día +
/// 1 liga; Premium = histórico ilimitado, ligas ilimitadas, stats avanzadas".
final class FreemiumAccessTests: XCTestCase {

    private let calendar = PremiumFixtures.calendar

    private func access(
        plan: FreemiumPlan,
        nowOffsetDays days: Int,
        nowHour: Int = 12
    ) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: PremiumFixtures.anchorDate,
            now: PremiumFixtures.date(anchorOffsetDays: days, hour: nowHour),
            calendar: calendar
        )
    }

    // MARK: - Limits (S9 numbers)

    func testFreeLimitsMatchS9() {
        XCTAssertEqual(FreemiumLimits.fullHistoryGraceDays, 7)
        XCTAssertEqual(FreemiumLimits.freeHistoryDays, 1)
        XCTAssertEqual(FreemiumLimits.freeMaxLeagues, 1)
    }

    // MARK: - History during the grace window

    func testFreePlanSeesTheFullHistoryOnTheAnchorDay() {
        let sut = access(plan: .free, nowOffsetDays: 0)

        XCTAssertTrue(sut.isWithinFullHistoryGrace)
        XCTAssertEqual(sut.daysSinceAnchor, 0)
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: -400)))
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)))
    }

    func testFreePlanSeesTheFullHistoryOnDaySeven() {
        let sut = access(plan: .free, nowOffsetDays: 6, nowHour: 23)

        XCTAssertTrue(sut.isWithinFullHistoryGrace)
        XCTAssertEqual(sut.daysSinceAnchor, 6)
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: -30)))
    }

    // MARK: - History after the grace window

    func testFreePlanIsLimitedOnDayEight() {
        let sut = access(plan: .free, nowOffsetDays: 7)

        XCTAssertFalse(sut.isWithinFullHistoryGrace)
        XCTAssertEqual(sut.daysSinceAnchor, 7)
        XCTAssertFalse(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)))
        XCTAssertFalse(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 6)))
    }

    func testFreePlanSeesOnlyTheLastDayOnDayEight() {
        let sut = access(plan: .free, nowOffsetDays: 7, nowHour: 8)

        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 7, hour: 0)))
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 7, hour: 23)))
        XCTAssertEqual(
            sut.firstVisibleFreeDay,
            calendar.startOfDay(for: PremiumFixtures.date(anchorOffsetDays: 7))
        )
    }

    func testFreePlanCannotSeeTomorrow() {
        let sut = access(plan: .free, nowOffsetDays: 20)

        XCTAssertFalse(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 21)))
    }

    func testPremiumPlanSeesTheFullHistoryForever() {
        let sut = access(plan: .premium, nowOffsetDays: 400)

        XCTAssertTrue(sut.isPremium)
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: -1_000)))
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 0)))
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: 400)))
    }

    func testGraceIsTrueForPremiumRegardlessOfTheAnchor() {
        XCTAssertTrue(access(plan: .premium, nowOffsetDays: 90).isWithinFullHistoryGrace)
    }

    // MARK: - Leagues (S9: free = 1 league)

    func testFreePlanCanCreateTheFirstLeagueOnly() {
        let sut = access(plan: .free, nowOffsetDays: 30)

        XCTAssertTrue(sut.canCreateLeague(count: 0))
        XCTAssertFalse(sut.canCreateLeague(count: 1))
        XCTAssertFalse(sut.canCreateLeague(count: 2))
    }

    func testFreePlanLeagueCapAlsoAppliesDuringTheGraceWindow() {
        let sut = access(plan: .free, nowOffsetDays: 2)

        XCTAssertTrue(sut.canCreateLeague(count: 0))
        XCTAssertFalse(sut.canCreateLeague(count: 1))
    }

    func testPremiumPlanHasUnlimitedLeagues() {
        let sut = access(plan: .premium, nowOffsetDays: 30)

        XCTAssertTrue(sut.canCreateLeague(count: 0))
        XCTAssertTrue(sut.canCreateLeague(count: 25))
    }

    // MARK: - Advanced stats (S9: premium only)

    func testAdvancedStatsArePremiumOnly() {
        XCTAssertFalse(access(plan: .free, nowOffsetDays: 0).canUseAdvancedStats)
        XCTAssertFalse(access(plan: .free, nowOffsetDays: 30).canUseAdvancedStats)
        XCTAssertTrue(access(plan: .premium, nowOffsetDays: 30).canUseAdvancedStats)
    }

    // MARK: - Anchor edge cases

    func testAnchorInTheFutureStillShowsTheFullHistory() {
        let sut = FreemiumAccess(
            plan: .free,
            anchorDate: PremiumFixtures.date(anchorOffsetDays: 10),
            now: PremiumFixtures.date(anchorOffsetDays: 0),
            calendar: calendar
        )

        XCTAssertTrue(sut.isWithinFullHistoryGrace)
        XCTAssertTrue(sut.canViewHistory(date: PremiumFixtures.date(anchorOffsetDays: -5)))
    }

    // MARK: - Streak freezes (S1/S8)

    func testWeeklyFreezesMatchS8() {
        XCTAssertEqual(FreemiumLimits.freeWeeklyFreezes, 1)
        XCTAssertEqual(FreemiumLimits.premiumWeeklyFreezes, 3)
        XCTAssertEqual(FreemiumLimits.weeklyFreezes(for: .free), 1)
        XCTAssertEqual(FreemiumLimits.weeklyFreezes(for: .premium), 3)

        XCTAssertEqual(access(plan: .free, nowOffsetDays: 0).weeklyFreezes, 1)
        XCTAssertEqual(access(plan: .premium, nowOffsetDays: 0).weeklyFreezes, 3)
    }

    // MARK: - Streak repair (S8)

    /// 2026-03-04 12:00 UTC.
    private var repairNow: Date {
        PremiumFixtures.date(anchorOffsetDays: 3, hour: 12)
    }

    /// 2026-03-03 09:00 UTC: the day that broke the run, still inside the 48 h
    /// window of the repair.
    private var brokenYesterday: Date {
        PremiumFixtures.date(anchorOffsetDays: 2, hour: 9)
    }

    private func repairAccess(plan: FreemiumPlan) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: PremiumFixtures.anchorDate,
            now: repairNow,
            calendar: calendar
        )
    }

    func testTheRepairWindowAndCooldownMatchS8() {
        XCTAssertEqual(FreemiumLimits.streakRepairWindowHours, 48)
        XCTAssertEqual(FreemiumLimits.streakRepairCooldownDays, 30)
    }

    /// S8: repairing the streak is a Premium advantage.
    func testTheFreePlanCannotRepairTheStreak() {
        let sut = repairAccess(plan: .free)

        XCTAssertFalse(
            sut.canRepairStreak(brokenDay: brokenYesterday, lastRepairAt: nil, now: repairNow)
        )
    }

    func testPremiumCanRepairABreakInsideTheWindow() {
        let sut = repairAccess(plan: .premium)

        XCTAssertTrue(
            sut.canRepairStreak(brokenDay: brokenYesterday, lastRepairAt: nil, now: repairNow)
        )
    }

    /// S8: the 48 h window is counted from the end of the broken day.
    func testPremiumCannotRepairABreakOlderThanTheWindow() {
        let sut = repairAccess(plan: .premium)
        let tooOld = PremiumFixtures.date(anchorOffsetDays: 0, hour: 9)

        XCTAssertFalse(
            sut.canRepairStreak(brokenDay: tooOld, lastRepairAt: nil, now: repairNow)
        )
    }

    func testThereIsNothingToRepairWithoutABrokenDay() {
        let sut = repairAccess(plan: .premium)

        XCTAssertFalse(
            sut.canRepairStreak(brokenDay: nil, lastRepairAt: nil, now: repairNow)
        )
    }

    /// S8: "una vez cada 30 días".
    func testPremiumCannotRepairTwiceInsideThirtyDays() {
        let sut = repairAccess(plan: .premium)
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: repairNow) ?? repairNow
        let thirtyOneDaysAgo = calendar.date(byAdding: .day, value: -31, to: repairNow) ?? repairNow

        XCTAssertFalse(
            sut.canRepairStreak(brokenDay: brokenYesterday, lastRepairAt: tenDaysAgo, now: repairNow)
        )
        XCTAssertTrue(
            sut.canRepairStreak(brokenDay: brokenYesterday, lastRepairAt: thirtyOneDaysAgo, now: repairNow)
        )
    }
}
