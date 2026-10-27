import Combine
import Foundation

/// Builds the share card (S8) from the same read boundaries the screens use, so the
/// card can never show different numbers than Hoy and Ligas.
@MainActor
final class ShareCardViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido preparar tu tarjeta. Inténtalo de nuevo."

    @Published private(set) var card: ShareCardModel?

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    private let todayDataLoader: TodayDataLoading
    private let leaguesRepository: LeaguesDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        todayDataLoader: TodayDataLoading = SupabaseTodayRepository(),
        leaguesRepository: LeaguesDataLoading = SupabaseLeaguesRepository(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.todayDataLoader = todayDataLoader
        self.leaguesRepository = leaguesRepository
        self.calendar = calendar
        self.now = now
    }

    func load(userID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await TodaySnapshotLoader(
                dataLoader: todayDataLoader,
                calendar: calendar
            )
            .load(userID: userID, now: now())

            let position = await leaguePosition(userID: userID)

            card = ShareCardModel(
                score: snapshot.score,
                streakDays: snapshot.streak.days,
                leaguePosition: position?.rank,
                leagueName: position?.leagueName,
                leagueSize: position?.size ?? 0
            )
        } catch {
            errorMessage = Self.loadFailureMessage
        }
    }

    /// Weekly position of the user in their first league (S7). A failing ranking
    /// only drops the position: the card is still worth sharing.
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
            let mine = rows.first(where: { $0.userID == userID })
        else {
            return nil
        }

        return LeaguePosition(rank: mine.rank, leagueName: league.name, size: rows.count)
    }

    private struct LeaguePosition {
        let rank: Int
        let leagueName: String
        let size: Int
    }
}
