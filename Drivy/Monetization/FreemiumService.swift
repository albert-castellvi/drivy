import Combine
import Foundation

/// State machine of the freemium plan (S9).
enum FreemiumState: Equatable {
    /// Nothing read yet: the plan is not known.
    case unknown
    /// An entitlement read is in flight.
    case loading
    case free
    case premium
}

/// Source of truth of the freemium plan and the gating rules (S9).
///
/// StoreKit sits behind `PremiumEntitlementProviding`, the clock is injected and
/// the anchor date comes from the caller, so the whole state machine is pure
/// enough to be tested without StoreKit, without a network and without Supabase.
/// No backend entitlement table exists (S10 defines none): the plan is derived
/// from StoreKit entitlements only.
///
/// `state` and `access` are `@Published`, which is the change notification: a
/// SwiftUI view observing the service re-renders whenever the plan or the
/// gating rules change (refresh, purchase, restore, `Transaction.updates`).
///
/// Every plan read that ends in premium also schedules `PremiumSync` (S5.3):
/// the JWS of the verified current entitlement is posted to `verify-premium`
/// best effort, off the main flow, at launch after sign-in and on every
/// `Transaction.updates` event the listener already observes.
///
/// ## Hook points (parent wiring, out of T5 scope)
/// - Today / history: keep a day only when
///   `service.access?.canViewHistory(date: day) == true`, otherwise show
///   `PaywallCopy.historyLockedMessage` with a paywall entry point.
/// - Leagues: allow create/join only when
///   `service.access?.canCreateLeague(count: memberLeagues.count) == true`,
///   otherwise show `PaywallCopy.leagueLimitMessage`.
/// - Advanced stats: render them only when
///   `service.access?.canUseAdvancedStats == true`, otherwise
///   `PaywallCopy.advancedStatsLockedMessage`.
/// - Paywall: present it through `PaywallPresenter` after the first completed
///   drive. Gating must never block recording a drive (S9/S12).
@MainActor
final class FreemiumService: ObservableObject {

    @Published private(set) var state: FreemiumState = .unknown

    /// Gating snapshot for the current plan; `nil` until the plan is known.
    @Published private(set) var access: FreemiumAccess?

    private let store: PremiumEntitlementProviding
    private let calendar: Calendar
    private let now: () -> Date
    private var anchorDate: Date
    private var updateTask: Task<Void, Never>?

    /// Poster of the premium JWS to `verify-premium` (S5.3); a spy in tests.
    /// `nil` disables the sync entirely.
    private let premiumSync: PremiumSyncing?

    /// - Parameters:
    ///   - anchorDate: profile creation date, or the first drive date when the
    ///     profile is older. It starts the 7-day full-history window (S9).
    ///   - store: StoreKit boundary; a fake in tests.
    ///   - calendar: day grouping, injectable so tests pin it to UTC.
    ///   - now: clock, injectable so the window is asserted deterministically.
    ///   - premiumSync: `verify-premium` boundary (S5.3). The default is the
    ///     real best-effort sync; tests inject a spy or `nil`.
    init(
        anchorDate: Date,
        store: PremiumEntitlementProviding = StoreKitPremiumEntitlementProvider(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        premiumSync: PremiumSyncing? = PremiumSync()
    ) {
        self.anchorDate = anchorDate
        self.store = store
        self.calendar = calendar
        self.now = now
        self.premiumSync = premiumSync
    }

    /// Plan in force, or `nil` while it is still unknown/loading.
    var plan: FreemiumPlan? {
        switch state {
        case .free:
            return .free
        case .premium:
            return .premium
        case .unknown, .loading:
            return nil
        }
    }

    var isPremium: Bool {
        state == .premium
    }

    // MARK: - Reading the plan

    /// Reads the current entitlements and moves the machine out of `unknown`.
    /// Safe to call on launch and whenever the paywall closes.
    func refresh() async {
        state = .loading
        let entitlements = await store.activeEntitlements()
        apply(entitlements)
    }

    /// Re-anchors the 7-day window once the profile or the first drive date is
    /// known. No-op while the plan is still unknown.
    func updateAnchorDate(_ date: Date) {
        anchorDate = date
        guard let plan else { return }
        access = makeAccess(plan: plan)
    }

    /// Subscribes to `Transaction.updates` (S9). Idempotent: a second call while
    /// the listener is running does nothing.
    func startObservingEntitlementUpdates() {
        guard updateTask == nil else { return }

        let updates = store.entitlementUpdates()
        updateTask = Task { [weak self] in
            for await entitlements in updates {
                // Cancellation is cooperative: an element buffered before the
                // task started (or before stop) can still be delivered by
                // next(), so every element is re-checked against the flag
                // before it may touch the plan.
                guard let self, !Task.isCancelled else { return }
                self.apply(entitlements)
            }
        }
    }

    /// Cancels the listener (scene shutdown, tests).
    func stopObservingEntitlementUpdates() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - Purchase and restore

    /// Runs the StoreKit purchase and applies the resulting plan. Throws a
    /// `PaywallError` so the paywall can show Spanish copy; the plan is left
    /// untouched when the purchase does not complete.
    @discardableResult
    func purchase() async throws -> FreemiumPlan {
        let entitlements = try await store.purchase()
        apply(entitlements)
        return plan ?? .free
    }

    /// Restores previous purchases and applies the resulting plan.
    @discardableResult
    func restore() async throws -> FreemiumPlan {
        let entitlements = try await store.restore()
        apply(entitlements)
        return plan ?? .free
    }

    /// Storefront price for the paywall, `nil` when StoreKit cannot answer.
    func premiumDisplayPrice() async -> String? {
        await store.premiumDisplayPrice()
    }

    // MARK: - Internals

    private func apply(_ entitlements: [PremiumEntitlement]) {
        let plan: FreemiumPlan = PremiumProduct.grantsPremium(entitlements, at: now())
            ? .premium
            : .free
        state = (plan == .premium) ? .premium : .free
        access = makeAccess(plan: plan)

        // The launch read, a `Transaction.updates` event, a purchase and a
        // restore all end here: one hook covers every moment the server may
        // not have seen the current transaction yet (S5.3).
        guard plan == .premium else { return }
        schedulePremiumSync()
    }

    /// Posts the JWS of the verified current entitlement, best effort and off
    /// the state machine: a slow or failing network call must never delay the
    /// plan being applied (S5.3). `PremiumSync` dedupes per session.
    private func schedulePremiumSync() {
        guard let premiumSync else { return }

        let store = self.store
        Task {
            guard let jws = await store.verifiedPremiumJWS() else { return }
            await premiumSync.post(jws: jws)
        }
    }

    private func makeAccess(plan: FreemiumPlan) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: anchorDate,
            now: now(),
            calendar: calendar
        )
    }
}
