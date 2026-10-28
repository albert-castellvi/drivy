import SwiftUI

@main
struct DrivyApp: App {

    @StateObject private var auth = AuthViewModel()

    /// Sentry starts before any view exists, so a crash during launch is
    /// reported as well (S3). Under unit tests `start()` returns immediately.
    ///
    /// The navigation and tab chrome is set here for the same reason: an
    /// appearance proxy has to be configured before the first bar is built, and
    /// it is configured once (S3).
    init() {
        CrashReporting.start()
        DrivyAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                // S3: the whole app reads the road palette and Barlow from here,
                // so no screen repeats a tint or a body font.
                .tint(.drivyTint)
                .font(.drivyBody)
                .task { await auth.restoreSession() }
        }
    }
}
