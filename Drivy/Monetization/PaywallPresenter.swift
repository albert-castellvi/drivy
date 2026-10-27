import Foundation

/// Public entry point of the paywall (S9).
///
/// Other screens never build the paywall themselves and never talk to StoreKit:
/// they ask the presenter whether the paywall must be shown and, if so, present
/// the sheet it builds. The StoreKit wiring therefore lives in one place.
///
/// ```swift
/// // After a drive is uploaded (Today):
/// if PaywallPresenter.shouldPresent(completedDriveCount: drives.count,
///                                   plan: freemium.plan) {
///     isPaywallPresented = true
/// }
/// // Sheet content:
/// presenter.makePaywallView(onClose: { isPaywallPresented = false })
/// ```
@MainActor
struct PaywallPresenter {

    /// Shared freemium service, built once at launch next to the auth view
    /// model. Injected so tests and previews can pass their own.
    private let freemium: FreemiumService

    init(freemium: FreemiumService) {
        self.freemium = freemium
    }

    /// S9: the paywall appears after the first completed drive, and it never
    /// blocks recording one. `plan` is `nil` while the plan is still unknown.
    static func shouldPresent(completedDriveCount: Int, plan: FreemiumPlan?) -> Bool {
        completedDriveCount >= 1 && plan == .free
    }

    func makeViewModel() -> PaywallViewModel {
        PaywallViewModel(freemium: freemium)
    }

    /// Builds the sheet, ready to be presented with `.sheet(isPresented:)`.
    func makePaywallView(onClose: @escaping () -> Void = {}) -> PaywallView {
        PaywallView(viewModel: makeViewModel(), onClose: onClose)
    }
}
