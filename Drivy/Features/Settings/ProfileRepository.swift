import Foundation
import Supabase

/// Boundary between Ajustes and the profile row, so the visible name is tested
/// without a network (S2).
protocol ProfileDataLoading {

    /// `public.profiles.display_name` of the signed-in user.
    func displayName(userID: String) async throws -> String

    /// Writes `display_name`. It is the only column the client may update on its
    /// own profile: the migration revoked `update` on the rest of the table.
    func updateDisplayName(_ name: String, userID: String) async throws
}

enum ProfileRepositoryError: Error, Equatable {
    /// `handle_new_user` creates the row for every account, so nothing to read or
    /// nothing to update means the profile could not be reached, not that the user
    /// has no profile.
    case missingProfile
}

/// Read/write path of the visible name (S2).
///
/// Row Level Security limits `profiles` to the caller and the members of their
/// private leagues, so the filter by `id` is not optional: without it the read
/// would also return the names of the league mates.
struct SupabaseProfileRepository: ProfileDataLoading {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func displayName(userID: String) async throws -> String {
        let rows: [ProfileNameRow] = try await client
            .from("profiles")
            .select("display_name")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            throw ProfileRepositoryError.missingProfile
        }
        return row.displayName
    }

    func updateDisplayName(_ name: String, userID: String) async throws {
        // The payload carries one column on purpose: `authenticated` only holds
        // `update (display_name)` on this table, so anything else is refused.
        let response = try await client
            .from("profiles")
            .update(ProfileNameUpdate(displayName: name), count: .exact)
            .eq("id", value: userID)
            .execute()

        // A PATCH that matches no row still succeeds, so the count is the only way
        // to know the name was stored and the screen must not show a name the
        // leagues cannot read. A `nil` count means PostgREST sent no `Content-Range`:
        // it is taken as success, because the read that seeded the field already
        // proved the row exists.
        if response.count == 0 {
            throw ProfileRepositoryError.missingProfile
        }
    }

    private struct ProfileNameRow: Decodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private struct ProfileNameUpdate: Encodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}
