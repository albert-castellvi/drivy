import Foundation
import Supabase

/// Single Supabase client for the whole app.
///
/// Session persistence uses the supabase-swift defaults (Keychain storage), so
/// the user stays signed in across launches without any custom code.
enum SupabaseProvider {

    static let shared = SupabaseClient(
        supabaseURL: DrivyConfig.supabaseURL,
        supabaseKey: DrivyConfig.supabasePublishableKey
    )
}
