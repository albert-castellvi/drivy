import XCTest
@testable import Drivy

/// S1: the privacy manifest is what the App Store reads before accepting a binary
/// that touches a required-reason API without declaring it, so the declarations
/// are pinned here. It also states what the app sends to its own backend, which is
/// the App Store privacy questionnaire in executable form.
final class PrivacyManifestTests: XCTestCase {

    private static let userDefaultsCategory = "NSPrivacyAccessedAPICategoryUserDefaults"
    /// The accesses are the app's own preferences only (the freemium anchor, the
    /// paywall flag and the reminder flag); no data is shared with anyone.
    private static let userDefaultsReason = "CA92.1"

    private static let collectedUserID = "NSPrivacyCollectedDataTypeUserID"
    private static let collectedInteraction = "NSPrivacyCollectedDataTypeProductInteraction"
    private static let collectedCrash = "NSPrivacyCollectedDataTypeCrashData"

    private static let purposeAppFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
    private static let purposeAnalytics = "NSPrivacyCollectedDataTypePurposeAnalytics"

    // MARK: - Reading

    /// The test bundle runs inside the app on CI (`TEST_HOST`), so the first place
    /// to look is the compiled bundle: that is the check that the manifest really
    /// ships. When the host is the app, a missing resource fails instead of
    /// silently reading the repository copy; the copy is only read by a run
    /// outside the host, the same way `InfoPlistTests` reads `Info.plist`.
    private func manifest() throws -> [String: Any] {
        let bundleIdentifier = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
        if bundleIdentifier == DrivyConfig.bundleIdentifier {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                "PrivacyInfo.xcprivacy is not in the app bundle"
            )
            return try Self.plist(at: url)
        }

        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Drivy/Resources/PrivacyInfo.xcprivacy")
        return try Self.plist(at: url)
    }

    private static func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "unreadable privacy manifest at \(url.path)")
    }

    private func accessedAPITypes(in manifest: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "NSPrivacyAccessedAPITypes is missing"
        )
    }

    private func collectedDataTypes(in manifest: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
            "NSPrivacyCollectedDataTypes is missing"
        )
    }

    private func collectedEntry(named name: String, in manifest: [String: Any]) throws -> [String: Any]? {
        try collectedDataTypes(in: manifest)
            .first { $0["NSPrivacyCollectedDataType"] as? String == name }
    }

    // MARK: - Tracking (S1)

    func testTrackingIsDeclaredOff() throws {
        let manifest = try manifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    }

    func testNoTrackingDomainsAreDeclared() throws {
        let manifest = try manifest()
        let domains = try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [String])

        XCTAssertTrue(domains.isEmpty)
    }

    func testNoCollectedTypeIsDeclaredForTracking() throws {
        let manifest = try manifest()

        for entry in try collectedDataTypes(in: manifest) {
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? "?"
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypeTracking"] as? Bool,
                false,
                "\(name) cannot be tracked"
            )
        }
    }

    // MARK: - Required-reason API (S1)

    func testUserDefaultsAccessIsDeclaredWithItsReason() throws {
        let manifest = try manifest()
        let entry = try XCTUnwrap(
            try accessedAPITypes(in: manifest).first {
                $0["NSPrivacyAccessedAPIType"] as? String == Self.userDefaultsCategory
            },
            "the UserDefaults category is not declared"
        )

        XCTAssertEqual(entry["NSPrivacyAccessedAPITypeReasons"] as? [String], [Self.userDefaultsReason])
    }

    // MARK: - Collected data (S1)

    /// The three things the app actually sends to its own backend: the account id,
    /// the summarized drive activity and the crash reports.
    func testWhatTheBackendReceivesIsDeclared() throws {
        let manifest = try manifest()

        for name in [Self.collectedUserID, Self.collectedInteraction, Self.collectedCrash] {
            XCTAssertNotNil(try collectedEntry(named: name, in: manifest), "\(name) is not declared")
        }
    }

    /// S12 of the MVP: the raw GPS samples never leave the device, so there is no
    /// location data to declare. Declaring it anyway would put the app in a
    /// category it does not belong to.
    func testNoLocationDataIsDeclared() throws {
        let manifest = try manifest()

        for entry in try collectedDataTypes(in: manifest) {
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? ""
            XCTAssertFalse(
                name.lowercased().contains("location"),
                "location must not be declared as collected: \(name)"
            )
        }
    }

    func testTheAccountIdAndTheDriveActivityServeTheAppOnly() throws {
        let manifest = try manifest()

        for name in [Self.collectedUserID, Self.collectedInteraction] {
            let entry = try XCTUnwrap(try collectedEntry(named: name, in: manifest))
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                [Self.purposeAppFunctionality],
                "\(name) only exists to run the feature"
            )
        }
    }

    func testCrashDataAlsoServesAnalytics() throws {
        let manifest = try manifest()
        let entry = try XCTUnwrap(try collectedEntry(named: Self.collectedCrash, in: manifest))
        let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])

        XCTAssertTrue(purposes.contains(Self.purposeAppFunctionality))
        XCTAssertTrue(purposes.contains(Self.purposeAnalytics))
    }

    /// Neither advertising nor measurement: there is no ad SDK in the app and no
    /// data is sold or shared with a data broker.
    func testNoThirdPartyPurposeIsDeclared() throws {
        let manifest = try manifest()

        for entry in try collectedDataTypes(in: manifest) {
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? "?"

            XCTAssertFalse(
                purposes.contains("NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising"),
                "\(name) cannot be used for third-party advertising"
            )
            XCTAssertFalse(
                purposes.contains("NSPrivacyCollectedDataTypePurposeDeveloperAdvertising"),
                "\(name) cannot be used for our own advertising"
            )
        }
    }
}
