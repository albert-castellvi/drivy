import Foundation
import Sentry

/// The only place the app talks to the Sentry SDK (S3).
///
/// Everything else injects these functions, so the auth flow stays testable
/// without a started SDK, and the rest of the app never imports `Sentry`.
enum CrashReporting {

    /// Starts the SDK at launch so crashes, app hangs, handled errors and
    /// session health are reported (S3).
    ///
    /// Crash, app hang and auto session tracking are left at the SDK defaults.
    /// PII, screenshots and the view hierarchy are explicitly off: the app
    /// handles location data and the trees would leak it.
    static func start() {
        // Unit tests run inside the app process (TEST_HOST). A started SDK
        // would reach the network and mix test failures with real data.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        SentrySDK.start { options in
            options.dsn = DrivyConfig.sentryDSN
            options.environment = environmentName
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.tracesSampleRate = 0.2
        }
    }

    /// Reports a handled failure with the real error attached (S4).
    /// A no-op while the SDK is not started, which is the unit test case.
    static func capture(_ error: Error) {
        SentrySDK.capture(error: error)
    }

    /// Sets the signed-in user id, or clears it when `nil` (S4).
    ///
    /// Only the Supabase id is sent: never the email.
    static func setUser(id: String?) {
        guard let id = id else {
            SentrySDK.setUser(nil)
            return
        }
        // Fully qualified on purpose: Supabase also exports a `User` type.
        SentrySDK.setUser(Sentry.User(userId: id))
    }

    // MARK: - Environment

    /// `debug` for debug builds, `testflight` for a sandbox receipt (the
    /// App Store receipt a TestFlight build carries) and `production` for an
    /// App Store build.
    private static var environmentName: String {
        #if DEBUG
        return "debug"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return "production"
        #endif
    }
}
