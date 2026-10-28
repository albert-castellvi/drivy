import SwiftUI

/// Button styles of the app (S1): Liquid Glass on iOS 26, today's look before.
///
/// The app deploys to iOS 17, so the Liquid Glass button style of iOS 26 is
/// applied only where the runtime has it and every call site keeps exactly its
/// current `.borderedProminent` appearance otherwise.
///
/// What the call sites keep doing: the label owns the layout (the usual
/// `.frame(maxWidth: .infinity)` for full-width buttons). The glass shape adds
/// roughly 13 pt of internal padding around the label; it does not replace it.
///
/// Use it on fixed chrome only (bottom bars, sheets without scrolling). Actions
/// inside a `ScrollView` or `List` keep the bordered styles: glass on scrolling
/// content causes visual glitches and a performance cost.
extension View {

    /// Primary action: `.glassProminent` on iOS 26, `.borderedProminent` before.
    @ViewBuilder
    func glassProminentOrBorderedProminent() -> some View {
        // Filled with the sign blue in both modes: the dark-mode tint is a light
        // blue meant for text, and white on it fails contrast.
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent).tint(Color.drivySignBlue)
        } else {
            self.buttonStyle(.borderedProminent).tint(Color.drivySignBlue)
        }
    }
}
