import Foundation

/// Read-only app metadata for the UI (version row in Ajustes).
enum AppInfo {

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// e.g. `0.1.0 (1)`
    static var versionText: String {
        "\(shortVersion) (\(buildNumber))"
    }
}
