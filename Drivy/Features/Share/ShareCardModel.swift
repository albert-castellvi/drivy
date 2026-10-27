import Foundation

/// Everything the square share card renders (S8).
///
/// Plain values on purpose: the card can be asserted in tests without rendering an
/// image, and the view itself stays a dumb renderer of these numbers.
struct ShareCardModel: Equatable {

    /// Today's Driver Score (S6); `nil` when there is no drive today yet.
    let score: Int?

    let streakDays: Int

    /// 1-based position in the weekly ranking of the user's league (S7);
    /// `nil` without a league or without a drive this week.
    let leaguePosition: Int?

    let leagueName: String?

    let leagueSize: Int

    init(
        score: Int?,
        streakDays: Int,
        leaguePosition: Int?,
        leagueName: String?,
        leagueSize: Int
    ) {
        self.score = score
        self.streakDays = streakDays
        self.leaguePosition = leaguePosition
        self.leagueName = leagueName
        self.leagueSize = leagueSize
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

    var leagueText: String {
        guard let leaguePosition else {
            return "Sin liga esta semana"
        }
        guard let leagueName, !leagueName.isEmpty else {
            return "\(leaguePosition)º de la liga"
        }
        return "\(leaguePosition)º de \(leagueName)"
    }

    /// Text alternative of the image: what VoiceOver reads and what the share
    /// preview shows before the picture is drawn.
    var accessibilitySummary: String {
        "Driver Score \(scoreText). \(streakText). \(leagueText)."
    }
}
