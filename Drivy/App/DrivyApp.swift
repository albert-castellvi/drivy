import SwiftUI

@main
struct DrivyApp: App {

    @StateObject private var auth = AuthViewModel()

    /// Sentry starts before any view exists, so a crash during launch is
    /// reported as well (S3). Under unit tests `start()` returns immediately.
    init() {
        CrashReporting.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.restoreSession() }
        }
    }
}
