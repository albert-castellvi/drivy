import Foundation

/// Zone of one row of the public standings (S5), the `zone` column of
/// `public_league_standings()`.
///
/// `nil` on the row means "no movement": the row is neither in the promotion nor
/// in the demotion band of its division.
enum PublicLeagueZone: String, Decodable, Equatable {

    /// Top 7 of a division below Diamante (S5).
    case promotion

    /// Bottom 5 of a division above Bronce (S5).
    case demotion

    /// Text of the marked zone. Spanish, because it is user-facing copy.
    var label: String {
        switch self {
        case .promotion:
            return "Ascenso"
        case .demotion:
            return "Descenso"
        }
    }

    /// What the zone means, for the legend under the standings.
    var explanation: String {
        switch self {
        case .promotion:
            return "Los 7 primeros suben de división el lunes."
        case .demotion:
            return "Los 5 últimos bajan de división el lunes."
        }
    }

    var symbolName: String {
        switch self {
        case .promotion:
            return "arrow.up.circle.fill"
        case .demotion:
            return "arrow.down.circle.fill"
        }
    }
}

/// Whether the user plays the public leagues (S5, L9).
///
/// The three states come straight from `public.public_league_entries`: no row is
/// `undecided`, and the row's `opted_in` says the rest. The UI shows the
/// invitation only while the question has never been answered.
enum PublicLeagueDecision: Equatable {

    case undecided

    case optedIn

    case optedOut
}

/// Own row of `public.public_league_entries` (S5): the decision and the division
/// the user is in. The table has no public read policy beyond the own row, so
/// every row decoded here is the caller's.
struct PublicLeagueStatus: Decodable, Equatable {

    /// 1 Bronce … 5 Diamante (S5).
    let division: Int

    let optedIn: Bool

    enum CodingKeys: String, CodingKey {
        case division
        case optedIn = "opted_in"
    }

    init(division: Int, optedIn: Bool) {
        self.division = division
        self.optedIn = optedIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `division` is a smallint, which PostgREST can serialize as a number or
        // as a string.
        division = try container.decodeInteger(forKey: .division)
        optedIn = try container.decode(Bool.self, forKey: .optedIn)
    }
}

/// Result of `public_league_current()` (S5): the group the caller plays this week.
struct PublicLeagueCurrent: Decodable, Equatable {

    let groupID: String

    /// `yyyy-MM-dd` of the Monday the group was formed, the week key the RPCs
    /// use. PostgREST hands a `date` back as text (see `DayKey`).
    let weekStart: String

    /// Division of the group, 1…5 (S5).
    let division: Int

    /// Result of the last settled week: 1 promoted, -1 demoted, 0 stayed.
    let lastChange: Int

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case weekStart = "week_start"
        case division
        case lastChange = "last_change"
    }

    init(groupID: String, weekStart: String, division: Int, lastChange: Int) {
        self.groupID = groupID
        self.weekStart = weekStart
        self.division = division
        self.lastChange = lastChange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        groupID = try container.decode(String.self, forKey: .groupID)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        division = try container.decodeInteger(forKey: .division)
        lastChange = try container.decodeInteger(forKey: .lastChange)
    }
}

/// One row of `public_league_ranking()` (S5): a member of the caller's group.
///
/// The RPC marks the caller's own row with `is_me` and no longer returns anybody's
/// uuid, so a stranger in a public group cannot learn who is in it (S2).
struct PublicLeagueRankingRow: Decodable, Equatable, Identifiable {

    /// 1-based position inside the group.
    let place: Int

    /// Only the visible name is shown: the group never exposes more of the
    /// profile (S5, S2).
    let displayName: String

    /// XP earned inside the group's week (S4).
    let weekXP: Int

    /// `nil` when the row is outside both bands.
    let zone: PublicLeagueZone?

    /// True only on the caller's row (S2), which is what the view highlights.
    let isMe: Bool

    /// Stable identity of the row for `ForEach`: the place plus the visible name,
    /// the only two values the payload still carries (S2).
    var id: String { "\(place)-\(displayName)" }

    /// What the row shows on its trailing side.
    var xpText: String { LeagueXPText.format(weekXP) }

    enum CodingKeys: String, CodingKey {
        case place
        case displayName = "display_name"
        case weekXP = "week_xp"
        case zone
        case isMe = "is_me"
    }

    init(
        place: Int,
        displayName: String,
        weekXP: Int,
        zone: PublicLeagueZone?,
        isMe: Bool
    ) {
        self.place = place
        self.displayName = displayName
        self.weekXP = weekXP
        self.zone = zone
        self.isMe = isMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `place` and `week_xp` are bigints, so both shapes are accepted.
        place = try container.decodeInteger(forKey: .place)
        displayName = try container.decode(String.self, forKey: .displayName)
        weekXP = try container.decodeInteger(forKey: .weekXP)
        isMe = try container.decode(Bool.self, forKey: .isMe)
        // An unknown zone is read as "no zone" instead of failing the whole
        // standings: a future value must not blank the screen on an old build.
        zone = try container
            .decodeIfPresent(String.self, forKey: .zone)
            .flatMap { PublicLeagueZone(rawValue: $0) }
    }
}
