import Foundation

/// Static application configuration.
///
/// There are no secrets here: the Supabase publishable key is public by design
/// (it identifies the project, Row Level Security enforces access on the
/// server) so it is safe to commit. Nothing is read from the environment, which
/// keeps the generated Xcode project reproducible on CI (S11).
enum DrivyConfig {

    // MARK: - Supabase

    /// Project URL (L6). Kept as a string so tests can assert its shape before
    /// it is turned into a `URL`.
    static let supabaseURLString = "https://thsqgdaadhnnwsadjhrj.supabase.co"

    /// Public "publishable" key for the project above.
    static let supabasePublishableKey = "sb_publishable_mVEtT_CsRaZWaUwIz7XGjQ_fgm7z4Ly"

    /// Parsed Supabase project URL.
    static let supabaseURL: URL = {
        guard let url = URL(string: supabaseURLString) else {
            preconditionFailure("DrivyConfig.supabaseURLString is not a valid URL: \(supabaseURLString)")
        }
        return url
    }()

    // MARK: - App identity (S14, L5)

    /// Must match `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and the App Store
    /// Connect record.
    static let bundleIdentifier = "com.acrstudio.drivy"

    static let appDisplayName = "Drivy"

    static let xcodeScheme = "Drivy"

    /// Bundle identifier of the unit test bundle (asserted by `DrivyTests`).
    static let testBundleIdentifier = bundleIdentifier + ".tests"
}
