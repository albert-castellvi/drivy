import Combine
import Foundation

/// State of the Hoy tab (S1, S4, S6): today's Driver Score, the streak, the XP, the
/// quests of the day and the list of today's drives.
///
/// It owns the only write of the quest board: recording a quest is idempotent in
/// the shared data layer, and it is done here instead of in the loader so the read
/// path stays free of side effects (the share card reuses it).
@MainActor
final class TodayViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido cargar tu día. Desliza para reintentar."

    static let repairFailureMessage = "No hemos podido recuperar la racha. Inténtalo de nuevo."

    @Published private(set) var snapshot: TodaySnapshot = .empty

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    private let snapshotLoader: TodaySnapshotLoader
    private let progressLoader: ProgressDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        dataLoader: TodayDataLoading = SupabaseTodayRepository(),
        progressLoader: ProgressDataLoading = SupabaseProgressRepository(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.snapshotLoader = TodaySnapshotLoader(
            dataLoader: dataLoader,
            progressLoader: progressLoader,
            calendar: calendar
        )
        self.progressLoader = progressLoader
        self.calendar = calendar
        self.now = now
    }

    /// - Parameter plan: plan in force, which decides the weekly freezes (S1/S8).
    func load(userID: String, plan: FreemiumPlan? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await snapshotLoader.load(userID: userID, now: now(), plan: plan)
            snapshot = loaded
            await recordQuests(loaded.pendingQuestIDs, dayKey: loaded.dayKey)
        } catch {
            // A failed refresh must not blank the day the user is looking at: the
            // previous snapshot stays on screen next to the error.
            errorMessage = Self.loadFailureMessage
        }

        isLoading = false
    }

    /// S8: records the premium repair of the day that broke the run, then the
    /// caller reloads so the streak reflects it.
    func repairStreak(brokenDay: Date) async {
        let dayKey = DriveDay.key(for: brokenDay, calendar: calendar)

        do {
            try await progressLoader.recordStreakRepair(day: dayKey)
        } catch {
            errorMessage = Self.repairFailureMessage
        }
    }

    /// S6: stores the quests the day already satisfied. Idempotent, and the next
    /// load finds them recorded, so nothing is written twice.
    private func recordQuests(_ questIDs: [String], dayKey: String) async {
        guard !questIDs.isEmpty, !dayKey.isEmpty else { return }

        for questID in questIDs {
            // Best effort: a quest that cannot be stored is simply offered again
            // after the next refresh, which must never be an error on screen.
            try? await progressLoader.recordQuest(day: dayKey, questID: questID)
        }
    }
}
