import XCTest
@testable import Drivy

/// Exact Spanish copy of every paywall error (S9). The strings are asserted
/// verbatim so a rewrite of the UI copy cannot slip through unnoticed.
final class PaywallErrorTests: XCTestCase {

    func testCancellationShowsNoMessage() {
        XCTAssertNil(PaywallError.cancelled.message)
    }

    func testPendingPurchaseMessage() {
        XCTAssertEqual(
            PaywallError.pending.message,
            "Tu compra está pendiente de aprobación. Te avisaremos cuando se complete."
        )
    }

    func testProductUnavailableMessage() {
        XCTAssertEqual(
            PaywallError.productUnavailable.message,
            "La suscripción no está disponible ahora mismo. Inténtalo más tarde."
        )
    }

    func testVerificationFailureMessage() {
        XCTAssertEqual(
            PaywallError.verificationFailed.message,
            "No hemos podido verificar la compra. Inténtalo de nuevo."
        )
    }

    func testNetworkErrorMessage() {
        XCTAssertEqual(
            PaywallError.network.message,
            "No hay conexión. Comprueba tu red e inténtalo de nuevo."
        )
    }

    func testStoreUnavailableMessage() {
        XCTAssertEqual(
            PaywallError.storeUnavailable.message,
            "App Store no está disponible ahora mismo. Inténtalo más tarde."
        )
    }

    func testUnknownErrorMessage() {
        XCTAssertEqual(
            PaywallError.unknown.message,
            "No hemos podido completar la compra. Inténtalo de nuevo."
        )
    }

    func testEveryErrorExceptCancellationHasCopy() {
        let errors: [PaywallError] = [
            .cancelled,
            .pending,
            .productUnavailable,
            .verificationFailed,
            .network,
            .storeUnavailable,
            .unknown
        ]

        for error in errors where error != .cancelled {
            XCTAssertNotNil(error.message, "\(error) must have Spanish copy")
            XCTAssertFalse(error.message?.isEmpty ?? true, "\(error) copy must not be empty")
        }
    }
}
