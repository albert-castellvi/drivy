import XCTest
@testable import Drivy

/// The paywall copy is Spanish (S9) and lists exactly the three premium
/// benefits of the MVP. "Coach IA" is v1.1 and must not be advertised here.
final class PaywallCopyTests: XCTestCase {

    func testBenefitsMatchS9() {
        XCTAssertEqual(
            PaywallCopy.benefits,
            ["Histórico ilimitado", "Ligas ilimitadas", "Estadísticas avanzadas"]
        )
    }

    func testPaywallTitles() {
        XCTAssertEqual(PaywallCopy.title, "Hazte Premium")
        XCTAssertEqual(PaywallCopy.benefitsTitle, "Qué incluye")
    }

    func testPaywallButtons() {
        XCTAssertEqual(PaywallCopy.purchaseButtonTitle, "Suscribirme")
        XCTAssertEqual(PaywallCopy.restoreButtonTitle, "Restaurar compras")
        // S9/S12: the paywall is never blocking, it can always be dismissed.
        XCTAssertEqual(PaywallCopy.dismissButtonTitle, "Ahora no")
    }

    func testPaywallStatusMessages() {
        XCTAssertEqual(PaywallCopy.loadingPriceMessage, "Cargando el precio…")
        XCTAssertEqual(PaywallCopy.purchasingMessage, "Procesando la compra…")
        XCTAssertEqual(PaywallCopy.restoringMessage, "Restaurando las compras…")
        XCTAssertEqual(PaywallCopy.purchasedMessage, "¡Ya eres Premium! Gracias por apoyar Drivy.")
        XCTAssertEqual(PaywallCopy.premiumActiveMessage, "Tu suscripción Premium está activa.")
        XCTAssertEqual(
            PaywallCopy.restoreNothingFoundMessage,
            "No hemos encontrado ninguna compra que restaurar."
        )
        XCTAssertEqual(
            PaywallCopy.genericErrorMessage,
            "No hemos podido completar la compra. Inténtalo de nuevo."
        )
    }

    func testGatingMessagesForTheHookPoints() {
        XCTAssertEqual(
            PaywallCopy.historyLockedMessage,
            "Con el plan Free solo ves el día de hoy. Hazte Premium para ver todo tu histórico."
        )
        XCTAssertEqual(
            PaywallCopy.leagueLimitMessage,
            "El plan Free permite 1 liga. Hazte Premium para crear o unirte a más."
        )
        XCTAssertEqual(
            PaywallCopy.advancedStatsLockedMessage,
            "Las estadísticas avanzadas son Premium."
        )
    }
}
