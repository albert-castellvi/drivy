import Foundation

/// One StoreKit entitlement, reduced to the fields the freemium gate needs.
///
/// StoreKit types never reach the freemium service: verified `Transaction`s are
/// mapped to this value by `StoreKitPremiumEntitlementProvider`, which is what
/// keeps the state machine and the gating rules testable without StoreKit.
struct PremiumEntitlement: Equatable {

    /// Identifier of the purchased product.
    let productID: String

    /// End of the paid period; `nil` for a non-expiring purchase.
    let expirationDate: Date?

    /// Set when StoreKit reports the purchase as revoked (refund, removed from
    /// a family group). A revoked entitlement never grants premium.
    let revocationDate: Date?

    /// Raw JWS representation of the verified StoreKit transaction
    /// (`Transaction.jwsRepresentation`), or `nil` when the entitlement was
    /// built without one (tests, fixtures).
    ///
    /// The JWS is what `PremiumSync` sends to `verify-premium` so the server
    /// can build its own premium entitlement record (S5.3). It is signed by
    /// Apple and is the only server-checkable proof of the purchase.
    let jws: String?

    init(
        productID: String,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        jws: String? = nil
    ) {
        self.productID = productID
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.jws = jws
    }

    /// `true` while the entitlement is still paid for at `date`.
    func isActive(at date: Date) -> Bool {
        guard revocationDate == nil else { return false }
        guard let expirationDate else { return true }
        return expirationDate > date
    }

    // MARK: - Verified current JWS (S5.3)

    /// JWS of the entitlement that currently grants premium, or `nil` when no
    /// entitlement does.
    ///
    /// "Verified current" is the rule the freemium gate already runs: the
    /// entitlement must come from the premium product and be active (not
    /// expired, not revoked) at `date`. Expired, revoked or foreign-product
    /// transactions are never posted to `verify-premium`, even when StoreKit
    /// still lists them.
    static func verifiedCurrentJWS(
        in entitlements: [PremiumEntitlement],
        at date: Date
    ) -> String? {
        for entitlement in entitlements where PremiumProduct.grantsPremium(entitlement, at: date) {
            if let jws = entitlement.jws {
                return jws
            }
        }
        return nil
    }
}
