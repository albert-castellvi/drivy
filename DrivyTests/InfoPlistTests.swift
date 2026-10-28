import XCTest
@testable import Drivy

/// S12: the usage strings are the user-facing justification for the location and
/// motion permissions, and the `location` background mode is what keeps a drive
/// being recorded with the screen off. Pinning them here means a plist edit
/// cannot silently drop them.
///
/// S4 of the hardening: the strings describe what the app does. Recording starts
/// and stops with the user, and it continues in background only for a drive the
/// user started.
final class InfoPlistTests: XCTestCase {

    private static let whenInUse =
        "Drivy usa tu ubicación solo mientras registras un trayecto: tú lo inicias y tú lo paras, y con las muestras de GPS calcula la distancia y tu Driver Score. Las muestras se quedan en tu iPhone."
    private static let always =
        "Si eliges «Permitir siempre», Drivy sigue grabando el trayecto que tú has iniciado cuando bloqueas el iPhone o cambias de app. La grabación no se inicia sola, termina cuando tú la paras y se detiene si fuerzas el cierre de Drivy. Las muestras de GPS se quedan en tu iPhone."
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

    // MARK: - Location and motion (S12, S4)

    func testWhenInUseLocationDescription() throws {
        let info = try infoPlist()
        let value = try XCTUnwrap(info["NSLocationWhenInUseUsageDescription"] as? String)

        XCTAssertEqual(value, Self.whenInUse)
        // S4: the recording is started by the user, never detected.
        XCTAssertFalse(value.lowercased().contains("automátic"))
        // S12: the samples never leave the device.
        XCTAssertTrue(value.contains("se quedan en tu iPhone"))
    }

    func testAlwaysLocationDescriptionExplainsBackgroundRecording() throws {
        let info = try infoPlist()
        let value = try XCTUnwrap(info["NSLocationAlwaysAndWhenInUseUsageDescription"] as? String)

        XCTAssertEqual(value, Self.always)
        // The justification the App Store review looks for: a drive keeps being
        // recorded while the phone is locked (S12).
        XCTAssertTrue(value.contains("bloqueas el iPhone"))
        XCTAssertTrue(value.contains("grabando el trayecto"))
        // S4: no promise of automatic detection and none of recording while the
        // app is not in memory, which the code cannot keep.
        XCTAssertFalse(value.lowercased().contains("automátic"))
        XCTAssertFalse(value.lowercased().contains("app cerrada"))
        XCTAssertTrue(value.contains("se quedan en tu iPhone"))
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
