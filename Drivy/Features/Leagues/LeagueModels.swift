import Foundation

/// Row of `public.leagues` (S7). Only the columns the screens need are selected.
struct LeagueRecord: Decodable, Equatable, Identifiable {

    let id: String

    let name: String

    let ownerID: String

    /// Code a friend types (or receives in the invite link) to join.
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerID = "owner_id"
        case inviteCode = "invite_code"
    }

    init(id: String, name: String, ownerID: String, inviteCode: String) {
        self.id = id
        self.name = name
        self.ownerID = ownerID
        self.inviteCode = inviteCode
    }
}

/// One row of `public.league_weekly_ranking(p_league_id, p_week_start)` (S5).
///
/// Private leagues now rank by weekly XP, exactly like the public ones: the old
/// distance-weighted score and the kilometres are gone, because any ranking that
/// grows with the distance driven invites the user to drive more (S4).
struct LeagueRankingRow: Decodable, Equatable, Identifiable {

    let rank: Int

    let userID: String

    let displayName: String

    /// XP earned inside the week the RPC was asked about (S4).
    let weekXP: Int

    var id: String { userID }

    /// What the row shows on its trailing side.
    var xpText: String { LeagueXPText.format(weekXP) }

    enum CodingKeys: String, CodingKey {
        case rank
        case userID = "user_id"
        case displayName = "display_name"
        case weekXP = "week_xp"
    }

    init(rank: Int, userID: String, displayName: String, weekXP: Int) {
        self.rank = rank
        self.userID = userID
        self.displayName = displayName
        self.weekXP = weekXP
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `rank` and `week_xp` are bigints, which PostgREST may serialize as
        // numbers or as strings.
        rank = try container.decodeInteger(forKey: .rank)
        userID = try container.decode(String.self, forKey: .userID)
        displayName = try container.decode(String.self, forKey: .displayName)
        weekXP = try container.decodeInteger(forKey: .weekXP)
    }
}

/// The one number both rankings sort by (S4), printed the same way in each of
/// them so the user reads a single currency.
///
/// Deliberately not locale-driven, like `DriveFormat`: the string is asserted in
/// tests and stays the same everywhere.
enum LeagueXPText {

    static func format(_ xp: Int) -> String {
        "\(xp) XP"
    }
}

/// Invite code of a league (S7).
///
/// Six characters that get typed by hand or read from a screenshot, so the
/// alphabet leaves out the glyphs that get confused: I/1 and O/0.
enum LeagueInviteCode {

    static let length = 6

    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// `randomIndex` is injected so a test can pin the injected code exactly.
    static func generate(
        randomIndex: (Int) -> Int = { limit in Int.random(in: 0..<limit) }
    ) -> String {
        var code = ""
        code.reserveCapacity(length)

        for _ in 0..<length {
            let raw = randomIndex(alphabet.count)
            let index = min(max(raw, 0), alphabet.count - 1)
            code.append(alphabet[index])
        }

        return code
    }

    /// User input arrives lowercase, with spaces, or pasted from a message.
    /// Only whitespace is stripped: a truly invalid character stays in the string
    /// so validation can reject the code instead of silently changing it.
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace && !$0.isNewline }
    }
}

/// S7 universal deep link: `https://drivy.app/l/{invite_code}`.
///
/// Registering it later needs the associated domain `applinks:drivy.app`
/// (the App ID capability plus `com.apple.developer.associated-domains` in
/// `Drivy/Resources/Drivy.entitlements`) and
/// `https://drivy.app/.well-known/apple-app-site-association` on the web side.
/// No entitlement change is part of T4: until the domain exists the same URL still
/// opens the App Store page, and the code can be pasted into the join field, which
/// `code(fromUserInput:)` already understands.
enum LeagueInviteLink {

    static let host = "drivy.app"

    static let pathPrefix = "/l/"

    static func url(forInviteCode code: String) -> URL? {
        let normalized = LeagueInviteCode.normalize(code)
        guard !normalized.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = pathPrefix + normalized
        return components.url
    }

    /// Code carried by an invite link, so an incoming universal link can be
    /// understood without extra parsing.
    static func inviteCode(from url: URL) -> String? {
        guard url.host?.lowercased() == host else { return nil }
        guard url.path.hasPrefix(pathPrefix) else { return nil }

        let code = LeagueInviteCode.normalize(String(url.path.dropFirst(pathPrefix.count)))
        return code.isEmpty ? nil : code
    }

    /// What the join field receives: either the bare code or the whole link.
    static func code(fromUserInput input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = inviteCode(from: url) {
            return code
        }
        return LeagueInviteCode.normalize(trimmed)
    }
}
