import Combine
import Foundation

/// Builds the share card (S9) from the same read boundaries the screens use, so the
/// card can never show different numbers than Hoy and Ligas.
///
/// The streak comes from the same `TodaySnapshotLoader` (v2 rule, S1) with the
/// plan in force, so the freezes count exactly as they do on Hoy. The public
/// division is an extra: a failing read only drops that line.
@MainActor
final class ShareCardViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido preparar tu tarjeta. Inténtalo de nuevo."

    @Published private(set) var card: ShareCardModel?

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    private let todayDataLoader: TodayDataLoading
    private let progressLoader: ProgressDataLoading
    private let leaguesRepository: LeaguesDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        todayDataLoader: TodayDataLoading = SupabaseTodayRepository(),
        progressLoader: ProgressDataLoading = SupabaseProgressRepository(),
        leaguesRepository: LeaguesDataLoading = SupabaseLeaguesRepository(),
        calendar: Calendar = .madrid,
        now: @escaping () -> Date = Date.init
    ) {
        self.todayDataLoader = todayDataLoader
        self.progressLoader = progressLoader
        self.leaguesRepository = leaguesRepository
        self.calendar = calendar
        self.now = now
    }

    /// - Parameter plan: plan in force, which decides the weekly freezes of the
    ///   streak (S1/S8).
    func load(userID: String, plan: FreemiumPlan? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await TodaySnapshotLoader(
                dataLoader: todayDataLoader,
                progressLoader: progressLoader,
                calendar: calendar
            )
            .load(userID: userID, now: now(), plan: plan)

            let position = await leaguePosition(userID: userID)
            let division = await divisionName()

            card = ShareCardModel(
                score: snapshot.score,
                streakDays: snapshot.streak.days,
                leaguePosition: position?.rank,
                leagueName: position?.leagueName,
                leagueSize: position?.size ?? 0,
                divisionName: division
            )
        } catch {
            errorMessage = Self.loadFailureMessage
        }
    }

    /// Weekly position of the user in their first league (S7). A failing ranking
    /// only drops the position: the card is still worth sharing.
    ///
    /// The row is found through `is_me`, which the RPC computes server-side (S2):
    /// the client no longer receives anybody's uuid to compare against.
    private func leaguePosition(userID: String) async -> LeaguePosition? {
        guard let league = (try? await leaguesRepository.leagues(userID: userID))?.first else {
            return nil
        }

        let weekStart = WeekBounds.mondayKey(for: now(), calendar: calendar)
        guard
            let rows = try? await leaguesRepository.weeklyRanking(
                leagueID: league.id,
                weekStart: weekStart
            ),
            let mine = rows.first(where: \.isMe)
        else {
            return nil
        }

        return LeaguePosition(rank: mine.rank, leagueName: league.name, size: rows.count)
    }

    /// S9: name of the public division, only when the user opted in. The read is a
    /// plain select of the own row (`LeaguesDataLoading.publicLeagueStatus()`),
    /// never `public_league_current()`, whose first call of the week changes the
    /// user's league state.
    private func divisionName() async -> String? {
        let result = try? await leaguesRepository.publicLeagueStatus()
        guard let status = result, status.optedIn else { return nil }

        return PublicLeagueDivision.name(for: status.division)
    }

    private struct LeaguePosition {
        let rank: Int
        let leagueName: String
        let size: Int
    }
}
