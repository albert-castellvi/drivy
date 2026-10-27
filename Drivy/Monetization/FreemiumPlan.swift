import Foundation

/// Plan the user is entitled to (S9).
enum FreemiumPlan: String, Equatable {
    case free
    case premium
}

/// Numeric limits of S9, in one place so the paywall copy, the gate and the
/// tests cannot drift apart.
enum FreemiumLimits {

    /// A free account keeps the full history during the first 7 days (S9).
    /// The window is counted in calendar days from the anchor date (profile
    /// creation, or the first drive when the profile is older): days 1 to 7 are
    /// full, from day 8 the free plan is limited.
    static let fullHistoryGraceDays = 7

    /// After the grace window a free account sees only the last day (S9).
    static let freeHistoryDays = 1

    /// A free account belongs to at most one league, created or joined (S9).
    /// This cap is a limit of the free plan itself, so it also applies during
    /// the 7-day history window.
    static let freeMaxLeagues = 1

    // MARK: - Streak (S8)

    /// Freezes ("hielos") of S1 the free plan gets each ISO week. They are not
    /// carried over to the next week, so the allowance is a weekly budget.
    static let freeWeeklyFreezes = 1

    /// Premium gets three freezes per week (S1, S8).
    static let premiumWeeklyFreezes = 3

    /// S8: a broken streak can be repaired once every 30 days.
    static let streakRepairCooldownDays = 30

    /// S8: the repair window, counted from the end of the day that broke the run
    /// (that is when the break is committed).
    static let streakRepairWindowHours = 48

    /// S1/S8: freezes of the week for one plan.
    static func weeklyFreezes(for plan: FreemiumPlan) -> Int {
        switch plan {
        case .free:
            return freeWeeklyFreezes
        case .premium:
            return premiumWeeklyFreezes
        }
    }
}

/// Snapshot of the gating rules for one plan (S9).
///
/// Pure value type: no StoreKit, no clock, no network. `FreemiumService` builds
/// it from the entitlements and the injected anchor date/reference date, and the
/// screens ask it their questions:
///
/// - history list and drive detail → `canViewHistory(date:)`
/// - "create league" / "join league" → `canCreateLeague(count:)`
/// - advanced stats → `canUseAdvancedStats`
/// - streak card → `weeklyFreezes` (S1) and `canRepairStreak(...)` (S8)
struct FreemiumAccess: Equatable {

    let plan: FreemiumPlan

    /// Start of the free history window: profile creation date, or the first
    /// drive date. There is no backend entitlement table, so the caller decides
    /// (see `FreemiumService.updateAnchorDate(_:)`).
    let anchorDate: Date

    /// Reference date of this snapshot.
    let now: Date

    let calendar: Calendar

    init(plan: FreemiumPlan, anchorDate: Date, now: Date, calendar: Calendar = .current) {
        self.plan = plan
        self.anchorDate = anchorDate
        self.now = now
        self.calendar = calendar
    }

    var isPremium: Bool {
        plan == .premium
    }

    /// Calendar days between the anchor day and the reference day. Negative
    /// when the anchor is in the future (clock skew, re-anchored window).
    var daysSinceAnchor: Int {
        let from = calendar.startOfDay(for: anchorDate)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// `true` while the full history is still visible: premium users forever,
    /// free users during the first `fullHistoryGraceDays` days (S9).
    var isWithinFullHistoryGrace: Bool {
        isPremium || daysSinceAnchor < FreemiumLimits.fullHistoryGraceDays
    }

    /// First day a free account may still see after the grace window.
    var firstVisibleFreeDay: Date {
        let today = calendar.startOfDay(for: now)
        let offset = -(FreemiumLimits.freeHistoryDays - 1)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// Gating of the history list and the drive detail (S9).
    ///
    /// Premium: every day. Free inside the window: every day. Free after it:
    /// only the last day, never a future one.
    func canViewHistory(date: Date) -> Bool {
        if isPremium { return true }
        if isWithinFullHistoryGrace { return true }

        let day = calendar.startOfDay(for: date)
        return day >= firstVisibleFreeDay && day <= calendar.startOfDay(for: now)
    }

    /// Gating of a new league, either created or joined (S9).
    ///
    /// `count` is how many leagues the user already belongs to.
    func canCreateLeague(count: Int) -> Bool {
        if isPremium { return true }
        return count < FreemiumLimits.freeMaxLeagues
    }

    /// Advanced stats are premium only (S9).
    var canUseAdvancedStats: Bool {
        isPremium
    }

    // MARK: - Streak (S8)

    /// S1/S8: freezes the plan has this ISO week. Free 1, Premium 3.
    var weeklyFreezes: Int {
        FreemiumLimits.weeklyFreezes(for: plan)
    }

    /// S8: repairing a broken streak is a Premium advantage, only inside the 48 h
    /// that follow the end of the broken day, and at most once every 30 days.
    ///
    /// `brokenDay` is the day the run broke (`Streak.repairableDay` holds the same
    /// day when it is still inside the window); it is a parameter because the
    /// window is a property of that day, not of the snapshot.
    /// `lastRepairAt` is the newest row of `public.streak_repairs`, `nil` when the
    /// user never used the repair.
    func canRepairStreak(brokenDay: Date?, lastRepairAt: Date?, now repairNow: Date) -> Bool {
        guard isPremium, let brokenDay else { return false }

        // S8: the break happens when the broken day ends, so the window opens there.
        guard
            let brokenDayEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: brokenDay)
            ),
            let deadline = calendar.date(
                byAdding: .hour,
                value: FreemiumLimits.streakRepairWindowHours,
                to: brokenDayEnd
            ),
            repairNow < deadline
        else {
            return false
        }

        guard let lastRepairAt else { return true }
        guard
            let nextAllowed = calendar.date(
                byAdding: .day,
                value: FreemiumLimits.streakRepairCooldownDays,
                to: lastRepairAt
            )
        else {
            return false
        }
        return repairNow >= nextAllowed
    }
}
