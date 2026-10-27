import Foundation

/// Presentation gate of the paywall (S9).
///
/// S9 asks for the paywall after the first completed drive and never as a blocker:
/// this decides *whether* it is due, and remembers that it was already shown so it
/// does not come back on every launch or on every later drive. Recording is never
/// touched: the recorder runs before this is asked and keeps running after.
///
/// The "already shown" flag is persisted (`UserDefaults`), which is what makes it
/// "once ever" instead of "once per launch".
struct FirstDrivePaywallGate {

    /// Persisted flag of the paywall shown after the first drive.
    static let shownDefaultsKey = "drivy.freemium.paywallShownAfterFirstDrive"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `true` the first time S9's rule matches, and never again.
    ///
    /// `plan` is `nil` while the plan is still unknown, and a drive count of 0 means
    /// there is no completed drive yet: neither case is marked as shown, so the
    /// paywall is still due once the plan or the first drive arrives.
    ///
    /// Main-actor isolated because the S9 rule itself lives in `PaywallPresenter`,
    /// and this gate must not restate it.
    @MainActor
    func shouldPresent(completedDriveCount: Int, plan: FreemiumPlan?) -> Bool {
        guard !wasPresented else { return false }
        return PaywallPresenter.shouldPresent(completedDriveCount: completedDriveCount, plan: plan)
    }

    /// Records that the paywall was presented. Called by the screen right before
    /// presenting it, never by the gate itself.
    func markPresented() {
        defaults.set(true, forKey: Self.shownDefaultsKey)
    }

    var wasPresented: Bool {
        defaults.bool(forKey: Self.shownDefaultsKey)
    }
}
