import Combine
import Foundation

/// State of the Camino tab (S3, S4): the habit path and the levels the user has
/// just reached.
///
/// It owns the only write of the path: recording a reached level is idempotent in
/// the shared data layer, and it is done here instead of in the engine so the rule
/// stays pure and testable without a network (same shape as `TodayViewModel` with
/// the quests).
@MainActor
final class HabitPathViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido cargar tu camino. Desliza para reintentar."

    @Published private(set) var snapshot: HabitPathSnapshot = .empty

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    private let progressLoader: ProgressDataLoading
    private let calendar: Calendar
    private let now: () -> Date

    init(
        progressLoader: ProgressDataLoading = SupabaseProgressRepository(),
        calendar: Calendar = .madrid,
        now: @escaping () -> Date = Date.init
    ) {
        self.progressLoader = progressLoader
        self.calendar = calendar
        self.now = now
    }

    /// Reads the path of the signed-in user and records what it found.
    ///
    /// No user id is needed: RLS limits every table of the loop to
    /// `user_id = auth.uid()`, and the shared layer relies on that (S12 of the MVP).
    func load() async {
        isLoading = true
        errorMessage = nil

        let reference = now()

        do {
            let levels = try await progressLoader.habitLevels()
            // Unit 1 counts every drive (S3), so the read starts at the shared
            // floor instead of a lookback window that could hide older drives.
            let drives = try await progressLoader.drives(since: HabitPathEngine.allDrivesSince)

            // The lesson only decorates the entry card of the tab, so a failed read
            // degrades that line instead of blanking the path (same stance as the
            // XP card of Hoy).
            let todayKey = DriveDay.key(for: reference, calendar: calendar)
            let lessonDayKeys = (try? await progressLoader.lessonDays(from: todayKey, to: todayKey)) ?? []

            let loaded = HabitPathEngine.path(
                drives: drives,
                levels: levels,
                hasLessonToday: lessonDayKeys.contains(todayKey),
                now: reference
            )
            snapshot = loaded
            await recordLevels(loaded.pendingLevels)
        } catch {
            // A failed refresh keeps the path the user is looking at: the previous
            // snapshot stays on screen next to the error.
            errorMessage = Self.loadFailureMessage
        }

        isLoading = false
    }

    /// S3/S4: stores the levels the engine found reached, lowest first, so the
    /// `completedAt` the server stamps is monotonic and the next unit opens in the
    /// order the path played them.
    private func recordLevels(_ pendingLevels: [PendingHabitLevel]) async {
        guard !pendingLevels.isEmpty else { return }

        for level in pendingLevels {
            // Best effort: a level that cannot be stored is offered again after the
            // next refresh, which must never be an error on screen.
            try? await progressLoader.recordHabitLevel(unit: level.unit.id, level: level.level)
        }
    }
}
