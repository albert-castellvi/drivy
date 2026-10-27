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

    init(productID: String, expirationDate: Date? = nil, revocationDate: Date? = nil) {
        self.productID = productID
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
    }

    /// `true` while the entitlement is still paid for at `date`.
    func isActive(at date: Date) -> Bool {
        guard revocationDate == nil else { return false }
        guard let expirationDate else { return true }
        return expirationDate > date
    }
}
