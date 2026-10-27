import XCTest
@testable import Drivy

/// S12: the usage strings are the user-facing justification for the location and
/// motion permissions, and the `location` background mode is what keeps a drive
/// being recorded with the screen off. Pinning them here means a plist edit
/// cannot silently drop them.
final class InfoPlistTests: XCTestCase {

    private static let whenInUse =
        "Drivy usa tu ubicación mientras conduces para registrar el trayecto y calcular tu Driver Score."
    private static let always =
        "Drivy registra tus trayectos automáticamente, también con la app cerrada. Elige «Siempre» para no perder ningún trayecto. Las muestras de GPS se quedan en tu iPhone."
    private static let motion =
        "Drivy usa el sensor de movimiento para detectar frenadas y aceleraciones bruscas y puntuar tu conducción."

    /// The test bundle runs inside the app on CI (`TEST_HOST`), so `Bundle.main`
    /// is the Drivy bundle itself (the strongest check: the compiled plist). The
    /// repository plist is only the fallback when the tests run outside the host.
    private func infoPlist() throws -> [String: Any] {
        if let bundleIdentifier = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String,
           bundleIdentifier == DrivyConfig.bundleIdentifier,
           let info = Bundle.main.infoDictionary {
            return info
        }

        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Drivy/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "unreadable Info.plist at \(url.path)")
    }

    // MARK: - Location and motion (S12)

    func testWhenInUseLocationDescription() throws {
        let info = try infoPlist()

        XCTAssertEqual(info["NSLocationWhenInUseUsageDescription"] as? String, Self.whenInUse)
    }

    func testAlwaysLocationDescriptionExplainsBackgroundRecording() throws {
        let info = try infoPlist()
        let value = try XCTUnwrap(info["NSLocationAlwaysAndWhenInUseUsageDescription"] as? String)

        XCTAssertEqual(value, Self.always)
        // The justification the App Store review looks for (S12).
        XCTAssertTrue(value.contains("trayectos"))
        XCTAssertTrue(value.contains("app cerrada"))
    }

    func testMotionDescriptionJustifiesCoreMotion() throws {
        let info = try infoPlist()

        XCTAssertEqual(info["NSMotionUsageDescription"] as? String, Self.motion)
    }

    func testLocationBackgroundModeIsDeclared() throws {
        let info = try infoPlist()

        XCTAssertEqual(info["UIBackgroundModes"] as? [String], ["location"])
    }

    // MARK: - Existing identity (S14), untouched by this change

    func testAppIdentityKeysAreStillDeclared() throws {
        let info = try infoPlist()

        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Drivy")
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "es")

        // Expanded in the built app, a build variable in the source plist.
        let bundleIdentifier = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        XCTAssertTrue(
            bundleIdentifier == DrivyConfig.bundleIdentifier
                || bundleIdentifier == "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "unexpected CFBundleIdentifier: \(bundleIdentifier)"
        )
    }
}
