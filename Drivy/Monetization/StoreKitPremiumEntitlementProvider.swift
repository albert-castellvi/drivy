import Foundation
import StoreKit

/// StoreKit 2 implementation of `PremiumEntitlementProviding` (S9).
///
/// This is the only file of the app that imports StoreKit: everything it
/// returns is mapped to `PremiumEntitlement` / `PaywallError`, which is why the
/// freemium gate and the paywall are tested without StoreKit.
///
/// ## StoreKit configuration file for local testing
///
/// CI (S11) does not use StoreKitTest: the freemium state machine and the
/// paywall run against `FakePremiumEntitlementProvider`, so no `.storekit`
/// configuration file is committed or copied into the bundle, and no test needs
/// a `SKTestSession`.
///
/// To exercise the real purchase flow locally:
///
/// 1. In Xcode, File ▸ New ▸ File ▸ StoreKit Configuration File, saved as
///    `Drivy/Monetization/premium.storekit`, with one auto-renewable
///    subscription in a group: product id
///    `com.acrstudio.drivy.premium.monthly`, €4.99, 1 month, and the three
///    benefits of S9 as the subscription's localised description.
/// 2. Select it in the `Drivy` scheme: Run ▸ Options ▸ StoreKit Configuration.
///    That selection lives in the scheme, which `project.yml` generates, so it
///    must be re-applied after `xcodegen generate` (or the scheme edited in
///    `project.yml` once the file exists — out of scope of T5).
/// 3. For automated tests, drive it with
///    `SKTestSession(configurationFileNamed: "premium")` from the `StoreKitTest`
///    framework in the test bundle instead of using this struct.
struct StoreKitPremiumEntitlementProvider: PremiumEntitlementProviding {

    private let productIdentifiers: [String]

    init(productIdentifiers: [String] = PremiumProduct.identifiers) {
        self.productIdentifiers = productIdentifiers
    }

    // MARK: - Entitlements

    /// `Transaction.currentEntitlements` is the only source of truth: it already
    /// excludes expired and revoked transactions, and unverified ones are
    /// dropped instead of trusted.
    func activeEntitlements() async -> [PremiumEntitlement] {
        var entitlements: [PremiumEntitlement] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            entitlements.append(
                PremiumEntitlement(transaction: transaction, jws: result.jwsRepresentation)
            )
        }

        return entitlements
    }

    func premiumDisplayPrice() async -> String? {
        await premiumProduct()?.displayPrice
    }

    // MARK: - Purchase

    func purchase() async throws -> [PremiumEntitlement] {
        guard let product = await premiumProduct() else {
            throw PaywallError.productUnavailable
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw PaywallError.from(error: error)
        }

        switch result {
        case .success(let verification):
            // Never grant premium on an unverified signature.
            guard case .verified(let transaction) = verification else {
                throw PaywallError.verificationFailed
            }
            await transaction.finish()
            return await activeEntitlements()
        case .userCancelled:
            throw PaywallError.cancelled
        case .pending:
            throw PaywallError.pending
        @unknown default:
            throw PaywallError.unknown
        }
    }

    // MARK: - Restore

    func restore() async throws -> [PremiumEntitlement] {
        do {
            try await AppStore.sync()
        } catch {
            throw PaywallError.from(error: error)
        }

        return await activeEntitlements()
    }

    // MARK: - Transaction listener

    /// `Transaction.updates` covers renewals, refunds, Ask to Buy approvals and
    /// purchases made on another device (S9). Finishing the transaction keeps
    /// StoreKit from replaying it on the next launch.
    func entitlementUpdates() -> AsyncStream<[PremiumEntitlement]> {
        // Explicit copy of `self` (a value type) so the escaping closures below
        // do not capture the instance implicitly.
        let provider = self

        return AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else { continue }
                    await transaction.finish()
                    continuation.yield(await provider.activeEntitlements())
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Verified current JWS

    /// JWS of the verified current entitlement that grants premium (S5.3).
    ///
    /// `currentEntitlements` already filters expired and revoked transactions,
    /// and the selection re-checks the premium product and validity, so an
    /// expired, revoked or foreign-product transaction is never posted to
    /// `verify-premium`.
    func verifiedPremiumJWS() async -> String? {
        await PremiumEntitlement.verifiedCurrentJWS(
            in: activeEntitlements(),
            at: Date()
        )
    }

    // MARK: - Internals

    private func premiumProduct() async -> Product? {
        do {
            return try await Product.products(for: productIdentifiers).first
        } catch {
            return nil
        }
    }
}

// MARK: - StoreKit → app types

extension PremiumEntitlement {

    /// Maps a *verified* StoreKit transaction. This is the only place where a
    /// StoreKit type crosses into the freemium domain. The signed JWS lives on
    /// the `VerificationResult`, not on the `Transaction`, so the caller passes it.
    init(transaction: Transaction, jws: String) {
        self.init(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            jws: jws
        )
    }
}

extension PaywallError {

    /// Maps a thrown StoreKit error to the Spanish paywall copy (S9). Unknown
    /// cases fall back to `storeUnavailable` / `unknown`, never to a silent
    /// success.
    static func from(error: Error) -> PaywallError {
        guard let storeKitError = error as? StoreKitError else {
            return .unknown
        }

        switch storeKitError {
        case .userCancelled:
            return .cancelled
        case .networkError:
            return .network
        case .notAvailableInStorefront:
            return .productUnavailable
        default:
            return .storeUnavailable
        }
    }
}
