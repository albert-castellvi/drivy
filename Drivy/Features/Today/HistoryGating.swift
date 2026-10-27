import Foundation

/// One row of the Histórico list (S9).
///
/// The list renders these with `ForEach(rows)`, so identity has to be stable
/// across the recomputation of `HistoryGating.rows` on every render: a row is
/// identified by the day it shows, never by its position.
enum HistoryRow: Equatable, Identifiable {

    /// A day the plan in force may see.
    case day(HistoryDay)

    /// Days hidden by the free plan, collapsed into a single upsell row: one lock
    /// per hidden day would bury the days the user can still see.
    case locked(hiddenDayCount: Int)

    /// Identity of the row: the `yyyy-MM-dd` key of the day, or `"locked"` for
    /// the upsell row. Day keys and the locked row cannot collide, and there is
    /// at most one locked row per list, so the two namespaces never meet.
    var id: String {
        switch self {
        case .day(let day):
            return day.dayKey
        case .locked:
            return "locked"
        }
    }
}

/// Gating of the Histórico list (S9).
///
/// The rule itself lives in `FreemiumAccess`; this only turns it into rows, so the
/// screen has nothing to decide and the exact Spanish copy is asserted in tests.
enum HistoryGating {

    /// Copy of the locked row: the S9 string from `PaywallCopy`, so the gate and the
    /// paywall cannot drift apart.
    static let lockedMessage = PaywallCopy.historyLockedMessage

    /// Rows for the plan in force, in the order the days were given (newest first).
    ///
    /// `access` is `nil` while the plan is still unknown: nothing is gated then,
    /// because hiding data before the plan has been read would break S9's "never
    /// blocking" rule in the opposite direction.
    static func rows(days: [HistoryDay], access: FreemiumAccess?) -> [HistoryRow] {
        guard let access else { return days.map(HistoryRow.day) }

        var rows: [HistoryRow] = []
        var hiddenDays = 0

        for day in days {
            if access.canViewHistory(date: day.date) {
                rows.append(.day(day))
            } else {
                hiddenDays += 1
            }
        }

        if hiddenDays > 0 {
            rows.append(.locked(hiddenDayCount: hiddenDays))
        }

        return rows
    }
}
