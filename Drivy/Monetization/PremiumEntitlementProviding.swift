import Foundation

/// Boundary between the freemium service and StoreKit 2 (S9).
///
/// Everything the gate needs is expressed in app types, so the freemium state
/// machine and the paywall run in unit tests against a fake and never load
/// StoreKit (CI needs no `StoreKitTest` session, see
/// `StoreKitPremiumEntitlementProvider`).
protocol PremiumEntitlementProviding {

    /// Snapshot of the entitlements StoreKit reports as current
    /// (`Transaction.currentEntitlements`), already verified.
    func activeEntitlements() async -> [PremiumEntitlement]

    /// Storefront-localised price of the premium product, or `nil` when
    /// StoreKit cannot answer (offline, product not configured yet).
    func premiumDisplayPrice() async -> String?

    /// Runs the purchase flow and returns the entitlements afterwards.
    /// Throws a `PaywallError` so the paywall can show Spanish copy.
    func purchase() async throws -> [PremiumEntitlement]

    /// Restores previous purchases and returns the entitlements afterwards.
    func restore() async throws -> [PremiumEntitlement]

    /// Transaction listener (`Transaction.updates`): renewals, refunds, Ask to
    /// Buy approvals and purchases made on another device.
    func entitlementUpdates() -> AsyncStream<[PremiumEntitlement]>

    /// JWS of the verified current entitlement that grants premium, or `nil`
    /// when none does (S5.3). `PremiumSync` posts it to `verify-premium`; the
    /// JWS is the only server-checkable proof of the purchase.
    func verifiedPremiumJWS() async -> String?
}

extension PremiumEntitlementProviding {

    /// Default for providers that exist only for previews and galleries: they
    /// carry no real transaction, so there is no JWS to post and the sync is a
    /// no-op for them (S5.3).
    func verifiedPremiumJWS() async -> String? {
        nil
    }
}
