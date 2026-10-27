import Foundation

/// Spanish copy of the paywall and of the gating hook points (S9: the UI is
/// Spanish, the code is English).
///
/// Kept in one place so the exact strings are asserted in unit tests and the
/// views have no literals to drift.
enum PaywallCopy {

    // MARK: - Paywall sheet

    static let title = "Hazte Premium"

    static let subtitle = "Saca partido a cada trayecto con Drivy Premium."

    static let benefitsTitle = "Qué incluye"

    /// The three premium benefits of the MVP, in the order of S9. "Coach IA" is
    /// v1.1 and is deliberately not advertised here.
    static let benefits = [
        "Histórico ilimitado",
        "Ligas ilimitadas",
        "Estadísticas avanzadas"
    ]

    static let purchaseButtonTitle = "Suscribirme"

    static let restoreButtonTitle = "Restaurar compras"

    /// S9/S12: the paywall is never blocking, so it can always be dismissed.
    static let dismissButtonTitle = "Ahora no"

    // MARK: - Paywall status

    static let loadingPriceMessage = "Cargando el precio…"

    static let purchasingMessage = "Procesando la compra…"

    static let restoringMessage = "Restaurando las compras…"

    static let purchasedMessage = "¡Ya eres Premium! Gracias por apoyar Drivy."

    static let premiumActiveMessage = "Tu suscripción Premium está activa."

    static let restoreNothingFoundMessage = "No hemos encontrado ninguna compra que restaurar."

    /// Fallback for an error that is not a `PaywallError`.
    static var genericErrorMessage: String {
        PaywallError.unknown.message ?? "No hemos podido completar la compra."
    }

    // MARK: - Gating hook points (parent wiring, out of T5 scope)

    static let historyLockedMessage =
        "Con el plan Free solo ves el día de hoy. Hazte Premium para ver todo tu histórico."

    static let leagueLimitMessage =
        "El plan Free permite 1 liga. Hazte Premium para crear o unirte a más."

    static let advancedStatsLockedMessage = "Las estadísticas avanzadas son Premium."

    // MARK: - Streak repair (S8)

    /// Button of the repair when the plan allows it.
    static let streakRepairButtonTitle = "Recuperar racha"

    /// Why the repair is on offer: the free plan sees this next to the upsell.
    static let streakRepairWindowMessage =
        "Tu racha se rompió hace menos de 48 horas. Puedes recuperarla."

    /// Free plan: the repair is a Premium advantage, so the card upsells it.
    static let streakRepairUpsellMessage =
        "Recuperar una racha rota es Premium. Puedes repararla durante las 48 horas siguientes."

    /// Premium, but the last repair is younger than the 30-day cooldown (S8).
    static let streakRepairCoolingDownMessage =
        "Solo puedes recuperar la racha una vez cada 30 días."
}
