import Combine
import Foundation

/// Drives `PaywallView`: purchase, restore and the Spanish status copy (S9).
///
/// All StoreKit access goes through `FreemiumService`, so the paywall can be
/// previewed and unit-tested with a fake provider.
@MainActor
final class PaywallViewModel: ObservableObject {

    /// UI status of the paywall sheet. Errors carry the copy to display.
    enum Status: Equatable {
        case idle
        case loadingPrice
        case purchasing
        case restoring
        case purchased
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Storefront price once StoreKit answers, the €4.99 copy until then.
    @Published private(set) var priceText: String = PremiumProduct.fallbackPriceText

    /// Plan in force; `nil` while the freemium service has not read StoreKit.
    @Published private(set) var plan: FreemiumPlan?

    let benefits = PaywallCopy.benefits

    private let freemium: FreemiumService
    private var didLoadPrice = false

    init(freemium: FreemiumService) {
        self.freemium = freemium
        self.plan = freemium.plan
    }

    /// `true` while a purchase or a restore is in flight.
    var isBusy: Bool {
        status == .purchasing || status == .restoring
    }

    /// Syncs the plan and reads the Storefront price once. Called from
    /// `PaywallView.task`, so the sheet is self-sufficient: it reads the plan
    /// when nobody has done it yet, and picks up a purchase made earlier.
    func loadPrice() async {
        if freemium.state == .unknown {
            await freemium.refresh()
        }
        plan = freemium.plan

        guard !didLoadPrice else { return }
        didLoadPrice = true

        status = .loadingPrice
        defer {
            if status == .loadingPrice { status = .idle }
        }

        guard let price = await freemium.premiumDisplayPrice(), !price.isEmpty else { return }
        priceText = "\(price)/mes"
    }

    /// Runs the purchase. A cancellation returns to `idle`: dismissing the
    /// payment sheet is not an error worth showing (S9/S12).
    func purchase() async {
        guard !isBusy else { return }

        status = .purchasing
        do {
            plan = try await freemium.purchase()
            status = .purchased
        } catch {
            // A failed purchase leaves the plan in force untouched.
            plan = freemium.plan
            status = failureStatus(for: error)
        }
    }

    /// Restores previous purchases. Nothing found is explained instead of
    /// silently doing nothing.
    func restore() async {
        guard !isBusy else { return }

        status = .restoring
        do {
            let restored = try await freemium.restore()
            plan = restored
            status = restored == .premium
                ? .purchased
                : .failed(PaywallCopy.restoreNothingFoundMessage)
        } catch {
            plan = freemium.plan
            status = failureStatus(for: error)
        }
    }

    // MARK: - Internals

    private func failureStatus(for error: Error) -> Status {
        let paywallError = (error as? PaywallError) ?? .unknown
        guard let message = paywallError.message else { return .idle }
        return .failed(message)
    }
}
