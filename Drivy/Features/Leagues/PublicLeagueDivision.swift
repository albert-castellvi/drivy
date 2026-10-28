import Foundation

/// Divisions and movement bands of the public leagues (S5).
///
/// Pure rules only: no network, no clock, so the screens and the tests read the
/// same numbers. The SQL side (`0002_duolingo_loop.sql`) stores the division as
/// a `smallint` between 1 and 5 and writes the band into `zone`; this is the
/// client's reading of both.
enum PublicLeagueDivision {

    /// Bronce, the entry division. It never demotes (S5).
    static let first = 1

    /// Diamante, the top division. It never promotes (S5).
    static let top = 5

    /// "grupos de unos 30 jugadores" (S5).
    static let maximumGroupSize = 30

    /// "Suben los 7 primeros" (S5).
    static let promotionCount = 7

    /// "bajan los 5 últimos" (S5).
    static let demotionCount = 5

    /// Division clamped to the range the server accepts. The column already
    /// holds 1…5, and a future tier (or a bad payload) must not crash a build
    /// that only knows five names.
    static func clamped(_ division: Int) -> Int {
        min(max(division, first), top)
    }

    /// Spanish name of the division (S5): 1 Bronce, 2 Plata, 3 Oro, 4 Platino,
    /// 5 Diamante.
    static func name(for division: Int) -> String {
        switch clamped(division) {
        case 2:
            return "Plata"
        case 3:
            return "Oro"
        case 4:
            return "Platino"
        case 5:
            return "Diamante"
        default:
            return "Bronce"
        }
    }

    /// Header of the public section, e.g. `División 2 · Plata`.
    static func title(for division: Int) -> String {
        "División \(clamped(division)) · \(name(for: division))"
    }

    /// Banner of `public_league_entries.last_change` (S5): `1` promoted, `-1`
    /// demoted, anything else stayed. `division` is where the user is now, so the
    /// sentence names the division they are looking at.
    static func changeBanner(lastChange: Int, division: Int) -> String {
        switch lastChange {
        case 1:
            return "Has subido a \(name(for: division))."
        case -1:
            return "Has bajado a \(name(for: division))."
        default:
            return "Te mantienes en \(name(for: division))."
        }
    }
}
