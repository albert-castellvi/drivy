#if DEBUG
import Foundation

/// StoreKit-free provider used by the SwiftUI previews only (debug builds).
///
/// Previews must render the paywall without a StoreKit configuration file and
/// without a `SKTestSession`, so they inject this fake instead of the live
/// `StoreKitPremiumEntitlementProvider`.
final class PreviewPremiumEntitlementProvider: PremiumEntitlementProviding {

    private let grantsPremium: Bool

    init(grantsPremium: Bool) {
        self.grantsPremium = grantsPremium
    }

    func activeEntitlements() async -> [PremiumEntitlement] {
        guard grantsPremium else { return [] }
        return [
            PremiumEntitlement(
                productID: PremiumProduct.monthlyIdentifier,
                expirationDate: Date().addingTimeInterval(30 * 86_400)
            )
        ]
    }

    func premiumDisplayPrice() async -> String? {
        nil
    }

    func purchase() async throws -> [PremiumEntitlement] {
        await activeEntitlements()
    }

    func restore() async throws -> [PremiumEntitlement] {
        await activeEntitlements()
    }

    func entitlementUpdates() -> AsyncStream<[PremiumEntitlement]> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension PaywallViewModel {

    /// Preview fixture: a paywall wired to the fake provider above.
    static func preview(plan: FreemiumPlan) -> PaywallViewModel {
        let service = FreemiumService(
            anchorDate: Date(),
            store: PreviewPremiumEntitlementProvider(grantsPremium: plan == .premium)
        )
        return PaywallViewModel(freemium: service)
    }
}
#endif
