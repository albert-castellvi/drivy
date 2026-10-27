import Foundation

/// Gating of league creation and join (S9).
///
/// The rule lives in `FreemiumAccess.canCreateLeague(count:)`; this is the thin
/// screen-facing wrapper, so the view has no rule of its own and the cap is
/// asserted with the same code the UI runs.
enum LeagueLimitGate {

    /// Copy shown when the cap blocks the action: the S9 string from `PaywallCopy`.
    static let limitMessage = PaywallCopy.leagueLimitMessage

    /// `true` when the plan in force cannot create or join another league.
    ///
    /// `access` is `nil` while the plan is still unknown: a StoreKit hiccup must
    /// never lock the user out, so an unknown plan gates nothing.
    static func isAtLimit(access: FreemiumAccess?, leagueCount: Int) -> Bool {
        guard let access else { return false }
        return !access.canCreateLeague(count: leagueCount)
    }
}
