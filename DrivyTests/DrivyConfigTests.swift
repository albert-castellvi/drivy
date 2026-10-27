import XCTest
@testable import Drivy

/// Config is the only place the app knows the backend; these tests pin the
/// values that CI and the App Store record depend on.
final class DrivyConfigTests: XCTestCase {

    // MARK: - Supabase endpoint (L6)

    func testSupabaseURLIsAValidHTTPSProjectURL() {
        XCTAssertEqual(DrivyConfig.supabaseURLString, "https://thsqgdaadhnnwsadjhrj.supabase.co")
        XCTAssertEqual(DrivyConfig.supabaseURL.scheme, "https")
        XCTAssertEqual(DrivyConfig.supabaseURL.host, "thsqgdaadhnnwsadjhrj.supabase.co")
        XCTAssertTrue(DrivyConfig.supabaseURL.path.isEmpty)
        XCTAssertEqual(DrivyConfig.supabaseURL.absoluteString, DrivyConfig.supabaseURLString)
    }

    func testPublishableKeyIsWellFormed() {
        let key = DrivyConfig.supabasePublishableKey

        XCTAssertTrue(key.hasPrefix("sb_publishable_"), "unexpected key kind: \(key)")
        XCTAssertGreaterThan(key.count, "sb_publishable_".count + 10)
        XCTAssertFalse(key.contains(" "), "key must not contain whitespace")
        XCTAssertEqual(key, key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - App identity (S14, L5)

    func testAppIdentityMatchesSpecS14() {
        XCTAssertEqual(DrivyConfig.bundleIdentifier, "com.acrstudio.drivy")
        XCTAssertEqual(DrivyConfig.appDisplayName, "Drivy")
        XCTAssertEqual(DrivyConfig.xcodeScheme, "Drivy")
    }

    /// Guards the bundle id wiring in `project.yml`: the test bundle id is
    /// derived from the app bundle id, so a typo in either one fails here.
    func testTestBundleIdentifierFollowsAppBundleIdentifier() {
        XCTAssertEqual(DrivyConfig.testBundleIdentifier, "com.acrstudio.drivy.tests")
        XCTAssertEqual(Bundle(for: DrivyConfigTests.self).bundleIdentifier, DrivyConfig.testBundleIdentifier)
    }
}
