import Foundation

/// Everything the square share card renders (S9).
///
/// Plain values on purpose: the card can be asserted in tests without rendering an
/// image, and the view itself stays a dumb renderer of these numbers.
struct ShareCardModel: Equatable {

    /// Today's Driver Score (S6); `nil` when there is no drive today yet.
    let score: Int?

    /// Days of the streak v2 (S1).
    let streakDays: Int

    /// 1-based position in the weekly ranking of the user's league (S7);
    /// `nil` without a league or without a drive this week.
    let leaguePosition: Int?

    let leagueName: String?

    let leagueSize: Int

    /// Name of the public division the user is in (S5, S9): Bronce … Diamante.
    /// `nil` when they never opted in to public leagues, which is also when the
    /// card prints no division at all.
    let divisionName: String?

    init(
        score: Int?,
        streakDays: Int,
        leaguePosition: Int?,
        leagueName: String?,
        leagueSize: Int,
        divisionName: String? = nil
    ) {
        self.score = score
        self.streakDays = streakDays
        self.leaguePosition = leaguePosition
        self.leagueName = leagueName
        self.leagueSize = leagueSize
        self.divisionName = divisionName
    }

    static let empty = ShareCardModel(
        score: nil,
        streakDays: 0,
        leaguePosition: nil,
        leagueName: nil,
        leagueSize: 0
    )

    // MARK: - Copy (Spanish, because it is what gets shared)

    var scoreText: String {
        DriveFormat.score(score)
    }

    var streakText: String {
        switch streakDays {
        case 0:
            return "Sin racha"
        case 1:
            return "1 día de racha"
        default:
            return "\(streakDays) días de racha"
        }
    }

    /// S9: the public division, when the user takes part in public leagues.
    var divisionText: String? {
        divisionName.map { "Liga \($0)" }
    }

    /// Private league line. It keeps its old meaning (weekly position) and is only
    /// printed when there is a position to show, unless there is no public
    /// division to print instead: the card always says where the user stands.
    var leagueText: String {
        guard let leaguePosition else {
            return "Sin liga esta semana"
        }
        guard let leagueName, !leagueName.isEmpty else {
            return "\(leaguePosition)º de la liga"
        }
        return "\(leaguePosition)º de \(leagueName)"
    }

    /// True when the private league line is worth a row of its own: with a public
    /// division on the card, an empty "no league" line would only add noise.
    var showsLeagueLine: Bool {
        divisionName == nil || leaguePosition != nil
    }

    /// Text alternative of the image: what VoiceOver reads and what the share
    /// preview shows before the picture is drawn.
    var accessibilitySummary: String {
        var parts = ["Driver Score \(scoreText)", streakText]
        if let divisionText {
            parts.append(divisionText)
        }
        if showsLeagueLine {
            parts.append(leagueText)
        }
        return parts.joined(separator: ". ") + "."
    }
}
