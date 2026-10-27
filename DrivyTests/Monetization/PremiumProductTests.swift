import XCTest
@testable import Drivy

/// The premium product of S9: identifier, price copy and entitlement matching.
final class PremiumProductTests: XCTestCase {

    private let now = PremiumFixtures.date(anchorOffsetDays: 0)

    func testMonthlyProductIdentifierMatchesAppStoreConnect() {
        XCTAssertEqual(PremiumProduct.monthlyIdentifier, "com.acrstudio.drivy.premium.monthly")
        XCTAssertEqual(PremiumProduct.identifiers, ["com.acrstudio.drivy.premium.monthly"])
    }

    func testFallbackPriceIsFourNinetyNinePerMonth() {
        XCTAssertEqual(PremiumProduct.fallbackPriceText, "4,99 €/mes")
    }

    // MARK: - Entitlement matching

    func testActiveMonthlyEntitlementGrantsPremium() {
        XCTAssertTrue(PremiumProduct.grantsPremium(PremiumFixtures.entitlement(), at: now))
    }

    func testExpiredEntitlementDoesNotGrantPremium() {
        let expired = PremiumEntitlement(
            productID: PremiumProduct.monthlyIdentifier,
            expirationDate: now.addingTimeInterval(-1)
        )

        XCTAssertFalse(PremiumProduct.grantsPremium(expired, at: now))
    }

    func testRevokedEntitlementDoesNotGrantPremium() {
        let revoked = PremiumEntitlement(
            productID: PremiumProduct.monthlyIdentifier,
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: now
        )

        XCTAssertFalse(PremiumProduct.grantsPremium(revoked, at: now))
    }

    func testEntitlementOfAnotherProductDoesNotGrantPremium() {
        let other = PremiumProduct.grantsPremium(
            PremiumFixtures.entitlement(productID: "com.acrstudio.drivy.premium.yearly"),
            at: now
        )

        XCTAssertFalse(other)
    }

    func testAnyActiveEntitlementGrantsPremium() {
        let entitlements = [
            PremiumFixtures.entitlement(productID: "com.acrstudio.drivy.other"),
            PremiumFixtures.entitlement()
        ]

        XCTAssertTrue(PremiumProduct.grantsPremium(entitlements, at: now))
        XCTAssertFalse(PremiumProduct.grantsPremium([], at: now))
    }

    // MARK: - Entitlement validity

    func testEntitlementWithoutExpirationIsActive() {
        let lifetime = PremiumEntitlement(productID: PremiumProduct.monthlyIdentifier)

        XCTAssertTrue(lifetime.isActive(at: now))
    }

    func testEntitlementExpiringExactlyNowIsNoLongerActive() {
        let expiring = PremiumEntitlement(
            productID: PremiumProduct.monthlyIdentifier,
            expirationDate: now
        )

        XCTAssertFalse(expiring.isActive(at: now))
    }
}
