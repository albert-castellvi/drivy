import SwiftUI

/// Button styles of the app (S1): Liquid Glass on iOS 26, today's look before.
///
/// The app deploys to iOS 17, so the Liquid Glass button styles of iOS 26 are
/// applied only where the runtime has them and every call site keeps exactly its
/// current `.borderedProminent` / `.bordered` appearance otherwise.
///
/// What the call sites keep doing: the label owns the layout (the usual
/// `.frame(maxWidth: .infinity)` for full-width buttons). The glass shape adds
/// roughly 13 pt of internal padding around the label; it does not replace it.
///
/// Deliberate deviation: the Liquid Glass guidance prefers glass on fixed chrome
/// only, while these styles are also used by actions that live inside the Hoy
/// scroll view and the Histórico list. One consistent button look is the
/// accepted trade-off of this pass (L5); the appearance is the only thing that
/// changes, and only on iOS 26.
extension View {

    /// Primary action: `.glassProminent` on iOS 26, `.borderedProminent` before.
    @ViewBuilder
    func glassProminentOrBorderedProminent() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary action: `.glass` on iOS 26, `.bordered` before.
    @ViewBuilder
    func glassOrBordered() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
