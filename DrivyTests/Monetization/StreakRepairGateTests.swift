import XCTest
@testable import Drivy

/// Gating of the premium streak repair (S8), with the same shape as
/// `LeagueLimitGate`.
final class StreakRepairGateTests: XCTestCase {

    private let calendar = PremiumFixtures.calendar

    private var now: Date {
        PremiumFixtures.date(anchorOffsetDays: 3, hour: 12)
    }

    /// The day the run broke: yesterday, so the 48 h window is still open.
    private var brokenDay: Date {
        PremiumFixtures.date(anchorOffsetDays: 2, hour: 9)
    }

    private func access(plan: FreemiumPlan) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: PremiumFixtures.anchorDate,
            now: now,
            calendar: calendar
        )
    }

    private func streak(repairableDay: Date?) -> Streak {
        Streak(
            days: 4,
            freezesUsedThisWeek: 0,
            freezesLeftThisWeek: 1,
            isTodayCounted: false,
            repairableDay: repairableDay
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    // MARK: - Decisions

    func testPremiumCanRepairABreakInsideTheWindow() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: brokenDay),
            access: access(plan: .premium),
            lastRepairAt: nil,
            now: now
        )

        XCTAssertEqual(decision, .allowed)
    }

    /// S8: the repair is a Premium advantage, so the free plan gets the upsell.
    func testTheFreePlanIsLocked() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: brokenDay),
            access: access(plan: .free),
            lastRepairAt: nil,
            now: now
        )

        XCTAssertEqual(decision, .locked)
        XCTAssertEqual(StreakRepairGate.upsellMessage, PaywallCopy.streakRepairUpsellMessage)
    }

    /// An unknown plan offers nothing: a StoreKit hiccup must not look like a
    /// broken streak, and it must not hand out a premium advantage either.
    func testAnUnknownPlanOffersNothing() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: brokenDay),
            access: nil,
            lastRepairAt: nil,
            now: now
        )

        XCTAssertEqual(decision, .unavailable)
    }

    func testABreakOutsideTheWindowHasNothingToRepair() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: nil),
            access: access(plan: .premium),
            lastRepairAt: nil,
            now: now
        )

        XCTAssertEqual(decision, .nothingToRepair)
    }

    /// S8: "una vez cada 30 días".
    func testPremiumInsideTheCooldownIsToldHowLongToWait() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: brokenDay),
            access: access(plan: .premium),
            lastRepairAt: daysAgo(10),
            now: now
        )

        XCTAssertEqual(decision, .coolingDown(availableInDays: 20))
    }

    func testTheCooldownExpiresAfterThirtyDays() {
        let decision = StreakRepairGate.decision(
            streak: streak(repairableDay: brokenDay),
            access: access(plan: .premium),
            lastRepairAt: daysAgo(31),
            now: now
        )

        XCTAssertEqual(decision, .allowed)
    }

    func testTheCopyComesFromThePaywallStrings() {
        XCTAssertEqual(StreakRepairGate.buttonTitle, PaywallCopy.streakRepairButtonTitle)
        XCTAssertEqual(PaywallCopy.streakRepairButtonTitle, "Recuperar racha")
    }
}
