import Combine
import Foundation

/// Weekly ranking of one league (S7), read from
/// `public.league_weekly_ranking(league_id, week_start)`.
@MainActor
final class LeagueRankingViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido cargar la clasificación."

    @Published private(set) var rows: [LeagueRankingRow] = []

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    /// Header of the list, e.g. `13 nov`.
    @Published private(set) var weekStartLabel = ""

    let leagueID: String

    private let repository: LeaguesDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        leagueID: String,
        repository: LeaguesDataLoading = SupabaseLeaguesRepository(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.leagueID = leagueID
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        let weekStart = WeekBounds.monday(for: now(), calendar: calendar)
        weekStartLabel = DriveFormat.shortDay(weekStart, calendar: calendar)

        do {
            rows = try await repository.weeklyRanking(
                leagueID: leagueID,
                weekStart: WeekBounds.mondayKey(for: now(), calendar: calendar)
            )
        } catch {
            errorMessage = Self.loadFailureMessage
        }

        isLoading = false
    }
}
