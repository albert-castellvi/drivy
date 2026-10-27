import Foundation

/// What the Hoy card does with the streak repair (S8).
enum StreakRepairDecision: Equatable {

    /// The repair can be recorded now.
    case allowed

    /// Free plan: the repair is a Premium advantage, so the card shows the upsell
    /// instead of the action.
    case locked

    /// Premium, but the last repair is younger than the 30-day cooldown.
    case coolingDown(availableInDays: Int)

    /// No break inside the S8 48 h window: nothing to repair.
    case nothingToRepair

    /// The plan is still unknown: the card offers nothing and decides again on the
    /// next render, because a StoreKit hiccup must never look like "no repair".
    case unavailable
}

/// Gating of the streak repair (S8), following `LeagueLimitGate`.
///
/// The rule lives in `FreemiumAccess.canRepairStreak(brokenDay:lastRepairAt:now:)`
/// and the broken day in `Streak.repairableDay`; this is the thin screen-facing
/// wrapper, so the card has no rule of its own and the exact Spanish copy comes
/// from `PaywallCopy`.
enum StreakRepairGate {

    static let upsellMessage = PaywallCopy.streakRepairUpsellMessage

    static let buttonTitle = PaywallCopy.streakRepairButtonTitle

    /// - Parameters:
    ///   - streak: current run; only its `repairableDay` matters here.
    ///   - access: gating snapshot of the plan; `nil` while it is unknown.
    ///   - lastRepairAt: newest row of `public.streak_repairs`.
    ///   - now: reference date of the decision.
    static func decision(
        streak: Streak,
        access: FreemiumAccess?,
        lastRepairAt: Date?,
        now: Date
    ) -> StreakRepairDecision {
        guard let access else { return .unavailable }
        guard let brokenDay = streak.repairableDay else { return .nothingToRepair }
        guard access.isPremium else { return .locked }

        if access.canRepairStreak(brokenDay: brokenDay, lastRepairAt: lastRepairAt, now: now) {
            return .allowed
        }

        // With a broken day inside the window, the only remaining brake is the
        // cooldown.
        return .coolingDown(
            availableInDays: availableInDays(lastRepairAt, now: now, calendar: access.calendar)
        )
    }

    /// Days until the cooldown of `FreemiumLimits.streakRepairCooldownDays` ends.
    private static func availableInDays(_ lastRepairAt: Date?, now: Date, calendar: Calendar) -> Int {
        guard
            let lastRepairAt,
            let nextAllowed = calendar.date(
                byAdding: .day,
                value: FreemiumLimits.streakRepairCooldownDays,
                to: lastRepairAt
            )
        else {
            return FreemiumLimits.streakRepairCooldownDays
        }

        let days = calendar.dateComponents([.day], from: now, to: nextAllowed).day ?? 0
        return max(1, days)
    }
}
