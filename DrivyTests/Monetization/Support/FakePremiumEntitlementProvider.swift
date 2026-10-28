import Foundation
@testable import Drivy

/// Test double of the StoreKit 2 boundary (S9).
///
/// The freemium state machine and the paywall are tested through this fake, so
/// the unit tests never load StoreKit and CI needs no `StoreKitTest` session.
final class FakePremiumEntitlementProvider: PremiumEntitlementProviding {

    enum FakeError: Error, Equatable {
        case boom
    }

    /// Snapshot returned by `activeEntitlements()`.
    var entitlements: [PremiumEntitlement] = []

    /// Storefront price the paywall shows; `nil` simulates an offline store.
    var displayPrice: String? = "4,99 €"

    var purchaseResult: Result<[PremiumEntitlement], Error> = .success([])
    var restoreResult: Result<[PremiumEntitlement], Error> = .success([])

    /// JWS returned by `verifiedPremiumJWS()`; `nil` simulates a session
    /// without a current premium entitlement.
    var verifiedJWS: String?

    private(set) var activeEntitlementsCallCount = 0
    private(set) var displayPriceCallCount = 0
    private(set) var purchaseCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var entitlementUpdatesCallCount = 0
    private(set) var verifiedJWSCallCount = 0

    /// When `true`, `purchase()` suspends until `resumePurchase()` is called, so
    /// tests can assert what happens while the StoreKit sheet is open.
    var suspendsPurchase = false

    private var updateContinuation: AsyncStream<[PremiumEntitlement]>.Continuation?
    private var purchaseContinuation: CheckedContinuation<Void, Never>?

    func activeEntitlements() async -> [PremiumEntitlement] {
        activeEntitlementsCallCount += 1
        return entitlements
    }

    func premiumDisplayPrice() async -> String? {
        displayPriceCallCount += 1
        return displayPrice
    }

    func purchase() async throws -> [PremiumEntitlement] {
        purchaseCallCount += 1
        if suspendsPurchase {
            await withCheckedContinuation { continuation in
                purchaseContinuation = continuation
            }
        }
        let purchased = try purchaseResult.get()
        entitlements = purchased
        return purchased
    }

    func restore() async throws -> [PremiumEntitlement] {
        restoreCallCount += 1
        let restored = try restoreResult.get()
        entitlements = restored
        return restored
    }

    func entitlementUpdates() -> AsyncStream<[PremiumEntitlement]> {
        entitlementUpdatesCallCount += 1
        return AsyncStream { continuation in
            updateContinuation = continuation
        }
    }

    func verifiedPremiumJWS() async -> String? {
        verifiedJWSCallCount += 1
        return verifiedJWS
    }

    /// Emits a `Transaction.updates` event to whoever is listening.
    func pushUpdate(_ entitlements: [PremiumEntitlement]) {
        updateContinuation?.yield(entitlements)
    }

    /// Lets a suspended `purchase()` finish.
    func resumePurchase() {
        purchaseContinuation?.resume()
        purchaseContinuation = nil
    }
}
