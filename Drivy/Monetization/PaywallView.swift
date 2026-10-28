import SwiftUI

/// Paywall sheet of the premium subscription (S9).
///
/// Preview-friendly: the view takes its view model, so a `#Preview` or a UI test
/// can wire it to a fake StoreKit provider instead of the live one. Screens do
/// not build it directly: they go through `PaywallPresenter`.
///
/// The road system reads here too (S5): the price in the display role, the
/// benefits as a list of blue information signs, and the purchase as the one
/// directional sign of the screen. Copy stays exactly as `PaywallCopy` writes it
/// (S6).
struct PaywallView: View {

    @ObservedObject private var viewModel: PaywallViewModel
    private let onClose: () -> Void

    /// - Parameters:
    ///   - viewModel: paywall state; `PaywallViewModel.preview()` in previews.
    ///   - onClose: dismissal of the sheet ("Ahora no"). The presentation itself
    ///     belongs to the caller.
    init(viewModel: PaywallViewModel, onClose: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    benefitsSection
                    statusSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color.drivyPaper)
            // S9/S12: the paywall never blocks the app, it is always dismissible.
            .paywallActionBar { actions }
            .navigationTitle(PaywallCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PaywallCopy.dismissButtonTitle, action: onClose)
                }
            }
        }
        .task { await viewModel.loadPrice() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PaywallCopy.subtitle)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)

            Text(viewModel.priceText)
                .font(.drivyDisplay)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(PaywallCopy.benefitsTitle)
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)

            ForEach(viewModel.benefits, id: \.self) { benefit in
                HStack(alignment: .center, spacing: 12) {
                    // The small information sign of the system, with the mark of
                    // what the plan includes; decorative, the line reads itself.
                    RoadSign(kind: .info(systemName: "checkmark"), size: RoadMetrics.minSignSize)

                    Text(benefit)
                        .font(.drivyBody)
                        .foregroundStyle(Color.drivyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .loadingPrice:
            statusLabel(PaywallCopy.loadingPriceMessage, showsSpinner: true)
        case .purchasing:
            statusLabel(PaywallCopy.purchasingMessage, showsSpinner: true)
        case .restoring:
            statusLabel(PaywallCopy.restoringMessage, showsSpinner: true)
        case .purchased:
            statusLabel(PaywallCopy.purchasedMessage, color: .drivyGo)
        case .failed(let message):
            statusLabel(message, color: .drivyAlertText)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if viewModel.plan == .premium {
                Text(PaywallCopy.premiumActiveMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
            } else {
                Button {
                    Task { await viewModel.purchase() }
                } label: {
                    Text(PaywallCopy.purchaseButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.directionSign)
                .disabled(viewModel.isBusy)
            }

            Button(PaywallCopy.restoreButtonTitle) {
                Task { await viewModel.restore() }
            }
            .font(.drivyFootnote)
            .disabled(viewModel.isBusy)
        }
        .padding()
    }

    // MARK: - Building blocks

    private func statusLabel(
        _ message: String,
        showsSpinner: Bool = false,
        color: Color = .drivyInkMuted
    ) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
            }

            Text(message)
                .font(.drivyFootnote)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Bottom action bar

private extension View {

    /// Action bar of the paywall (S9/S12).
    ///
    /// iOS 26 renders it as a real system bar: `safeAreaBar` reserves the space and
    /// draws the scroll-edge blur and the glass treatment behind the content, so the
    /// bar brings no material of its own. Earlier releases keep today's
    /// `safeAreaInset` plus its `.bar` background.
    @ViewBuilder
    func paywallActionBar<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) { bar() }
        } else {
            self.safeAreaInset(edge: .bottom) { bar().background(.bar) }
        }
    }
}

#if DEBUG
// The preview fixtures live in `PaywallPreviewSupport.swift` (debug builds
// only), so the previews are compiled only when that file is.
#Preview("Paywall — plan Free") {
    PaywallView(viewModel: .preview(plan: .free))
}

#Preview("Paywall — Premium") {
    PaywallView(viewModel: .preview(plan: .premium))
}
#endif
