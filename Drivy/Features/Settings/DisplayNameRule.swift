import Foundation

/// Rule of the name other drivers see in the leagues (S2).
///
/// The server owns the final word: `profiles_display_name_length` is
/// `char_length(btrim(display_name)) between 1 and 30`
/// (`supabase/migrations/20261028120000_security_hardening.sql`). The client
/// trims the same way before measuring, so a field never triggers a database
/// error the user cannot read.
enum DisplayNameRule {

    /// Same ceiling as the CHECK constraint.
    static let maxLength = 30

    /// Copy shown under the field. Kept here so tests assert the exact strings.
    static let emptyMessage = "El nombre visible no puede estar vacío."
    static let tooLongMessage = "El nombre visible no puede tener más de 30 caracteres."

    /// What `Guardar` may write, or why it must not.
    enum Validation: Equatable {
        case valid(name: String)
        case invalid(message: String)
    }

    /// Trims like `btrim`: the whitespace and newlines around the name.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates the content of the field.
    ///
    /// The length is counted in Unicode scalars, which is what Postgres counts
    /// in `char_length`: counting grapheme clusters here would accept a name of
    /// 30 emoji that the CHECK constraint then rejects.
    static func validate(_ raw: String) -> Validation {
        let name = normalized(raw)
        guard !name.isEmpty else {
            return .invalid(message: emptyMessage)
        }
        guard name.unicodeScalars.count <= maxLength else {
            return .invalid(message: tooLongMessage)
        }
        return .valid(name: name)
    }
}
