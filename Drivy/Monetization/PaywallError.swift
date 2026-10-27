import Foundation

/// Everything that can go wrong while buying (S9), mapped to the exact Spanish
/// copy the paywall shows.
///
/// The mapping from StoreKit errors lives with the StoreKit implementation
/// (`StoreKitPremiumEntitlementProvider.swift`), so this type and its copy stay
/// testable without StoreKit.
enum PaywallError: Error, Equatable {

    /// The user dismissed the payment sheet. Not an error worth showing, hence
    /// no message.
    case cancelled

    /// Ask to Buy / SCA waiting for approval.
    case pending

    /// The product is not available in this Storefront (or not configured yet).
    case productUnavailable

    /// StoreKit could not verify the transaction signature.
    case verificationFailed

    case network

    /// The store itself is unreachable or refused the request.
    case storeUnavailable

    case unknown

    /// Copy of the paywall status line; `nil` when nothing should be shown.
    var message: String? {
        switch self {
        case .cancelled:
            return nil
        case .pending:
            return "Tu compra está pendiente de aprobación. Te avisaremos cuando se complete."
        case .productUnavailable:
            return "La suscripción no está disponible ahora mismo. Inténtalo más tarde."
        case .verificationFailed:
            return "No hemos podido verificar la compra. Inténtalo de nuevo."
        case .network:
            return "No hay conexión. Comprueba tu red e inténtalo de nuevo."
        case .storeUnavailable:
            return "App Store no está disponible ahora mismo. Inténtalo más tarde."
        case .unknown:
            return "No hemos podido completar la compra. Inténtalo de nuevo."
        }
    }
}
