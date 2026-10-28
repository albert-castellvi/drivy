import Combine
import Foundation

/// State of the public league block of the Ligas tab (S5, L9).
///
/// Three situations, mirroring `public.public_league_entries`:
///
/// - never decided → the invitation card with "Unirme" / "Ahora no";
/// - opted in → division, one-time movement banner, group standings and the
///   days left in the week;
/// - opted out → nothing public, private leagues only.
///
/// The ranking of the group comes from `public_league_ranking()`, which already
/// marks each row with its promotion or demotion zone, so the view marks rows
/// instead of recomputing the bands.
@MainActor
final class PublicLeagueViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let loadFailureMessage = "No hemos podido cargar la liga pública. Desliza para reintentar."
    static let optInFailureMessage = "No hemos podido unirte a la liga pública. Inténtalo de nuevo."
    static let optOutFailureMessage = "No hemos podido guardar tu decisión. Inténtalo de nuevo."

    @Published private(set) var decision: PublicLeagueDecision = .undecided

    /// Group of the week; `nil` until the RPC answers or while not opted in.
    @Published private(set) var current: PublicLeagueCurrent?

    /// Standings of that group, best place first.
    @Published private(set) var ranking: [PublicLeagueRankingRow] = []

    /// Days until the next Monday 00:00 Madrid (S5).
    @Published private(set) var daysLeft = 0

    @Published private(set) var isLoading = false

    /// True while the opt-in/opt-out call is in flight, so the buttons cannot be
    /// tapped twice.
    @Published private(set) var isSubmitting = false

    @Published private(set) var errorMessage: String?

    /// The movement banner is dismissed by the user, not by the server: the RPC
    /// keeps `last_change` for the whole week, so the dismissal lives as long as
    /// this screen does.
    @Published private(set) var isChangeBannerVisible = false

    private let repository: LeaguesDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        repository: LeaguesDataLoading = SupabaseLeaguesRepository(),
        calendar: Calendar = PublicLeagueWeek.madridCalendar,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Copy

    /// Header of the public section, e.g. `División 2 · Plata`. Falls back to the
    /// plain title while the group of the week is still unknown, so a failed
    /// RPC never leaves a nameless section on screen.
    var divisionTitle: String {
        guard let current else { return "Liga pública" }
        return PublicLeagueDivision.title(for: current.division)
    }

    /// Sentence of the movement banner: subiste, bajaste, te mantienes (S5).
    var changeBannerText: String {
        guard let current else { return "" }
        return PublicLeagueDivision.changeBanner(
            lastChange: current.lastChange,
            division: current.division
        )
    }

    /// Countdown of the group, e.g. `Quedan 4 días de liga`.
    var daysLeftText: String {
        PublicLeagueWeek.daysLeftText(daysLeft)
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        daysLeft = PublicLeagueWeek.daysLeft(now: now(), calendar: calendar)

        do {
            let status = try await repository.publicLeagueStatus()
            guard let status, status.optedIn else {
                // No row means the user never decided; a row with `opted_in`
                // false means they said no. Both hide the public section.
                applyNotPlayed(status == nil ? .undecided : .optedOut)
                return
            }

            decision = .optedIn
            await loadCurrent()
        } catch {
            errorMessage = Self.loadFailureMessage
        }
    }

    private func applyNotPlayed(_ decision: PublicLeagueDecision) {
        self.decision = decision
        current = nil
        ranking = []
        isChangeBannerVisible = false
    }

    /// Reads the group of the week and its standings. The RPC is what settles the
    /// previous week (promotion/demotion) and places the user, so it is called
    /// before the standings.
    private func loadCurrent() async {
        do {
            current = try await repository.currentPublicLeague()
        } catch let failure as PublicLeagueFailure {
            if failure == .notOptedIn {
                // The server has the last word: the entry stopped being
                // opted in between the two calls.
                applyNotPlayed(.optedOut)
            } else {
                errorMessage = Self.loadFailureMessage
            }
            return
        } catch {
            errorMessage = Self.loadFailureMessage
            return
        }

        isChangeBannerVisible = true

        do {
            ranking = try await repository.publicLeagueRanking()
        } catch {
            ranking = []
            errorMessage = Self.loadFailureMessage
        }
    }

    // MARK: - Decision

    /// Opts in and loads the group of the current week. Returns true when the
    /// user is playing the public league afterwards.
    @discardableResult
    func join() async -> Bool {
        // A user who never had a row has no settled week behind them, so the
        // movement banner would only announce a move that never happened.
        let isFirstParticipation = decision == .undecided

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await repository.setPublicLeagueOptIn(true)
        } catch {
            errorMessage = Self.optInFailureMessage
            return false
        }

        decision = .optedIn
        await loadCurrent()

        if isFirstParticipation {
            isChangeBannerVisible = false
        }

        return errorMessage == nil
    }

    /// Opts out, which also removes the name from this week's group. Returns true
    /// when the decision was stored.
    @discardableResult
    func decline() async -> Bool {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await repository.setPublicLeagueOptIn(false)
        } catch {
            errorMessage = Self.optOutFailureMessage
            return false
        }

        applyNotPlayed(.optedOut)
        return true
    }

    /// Hides the movement banner until the screen is loaded again. `last_change`
    /// is not cleared server-side, so the banner is dismissed here instead.
    func dismissChangeBanner() {
        isChangeBannerVisible = false
    }
}
