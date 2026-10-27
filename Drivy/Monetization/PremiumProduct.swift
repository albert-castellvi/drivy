import Foundation

/// The premium product of the MVP (S9): one auto-renewable monthly
/// subscription at €4.99/month.
///
/// There is no entitlement table in Supabase (S10 defines none), so the plan is
/// derived from StoreKit entitlements only. The identifier must match the App
/// Store Connect record.
enum PremiumProduct {

    /// Auto-renewable monthly subscription, €4.99/month (S9).
    static let monthlyIdentifier = "com.acrstudio.drivy.premium.monthly"

    /// Identifiers requested from StoreKit.
    static let identifiers: [String] = [monthlyIdentifier]

    /// Paywall price copy used until StoreKit answers with the
    /// Storefront-localised `displayPrice` (or when it cannot answer offline).
    static let fallbackPriceText = "4,99 €/mes"

    /// `true` when the entitlement comes from the premium product and is still
    /// valid at `date`.
    static func grantsPremium(_ entitlement: PremiumEntitlement, at date: Date) -> Bool {
        entitlement.productID == monthlyIdentifier && entitlement.isActive(at: date)
    }

    /// `true` when at least one entitlement grants premium.
    static func grantsPremium(_ entitlements: [PremiumEntitlement], at date: Date) -> Bool {
        entitlements.contains { grantsPremium($0, at: date) }
    }
}
