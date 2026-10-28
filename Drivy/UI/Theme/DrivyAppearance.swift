import UIKit

/// The system chrome speaks the same typeface as the road (S3).
///
/// Called once at launch, before any view exists: `UINavigationBar` and
/// `UITabBarItem` take their fonts from an appearance proxy, which is the only
/// supported way to put a bundled font in the bar titles and the tab labels.
/// Colours come from the dynamic token, so the chrome follows the appearance
/// without a second table.
@MainActor
enum DrivyAppearance {

    private static var configured = false

    /// Barlow Condensed Bold for the navigation titles (inline and large) and
    /// Barlow Condensed SemiBold for the tab labels. Idempotent: a second call
    /// does nothing, so a preview or a test host can call it freely.
    static func configure() {
        guard !configured else { return }
        configured = true

        let bar = UINavigationBar.appearance()
        let ink = DrivyToken.ink.uiColor
        bar.titleTextAttributes = [
            .font: DrivyUIFont.condensedBold(17),
            .foregroundColor: ink
        ]
        bar.largeTitleTextAttributes = [
            .font: DrivyUIFont.condensedBold(32),
            .foregroundColor: ink
        ]

        let tab = UITabBarItem.appearance()
        let label = DrivyUIFont.condensedSemiBold(12)
        tab.setTitleTextAttributes([.font: label], for: .normal)
        tab.setTitleTextAttributes([.font: label], for: .selected)
    }
}
