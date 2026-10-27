import Combine
import Foundation

/// State of the Hoy tab (S6): today's Driver Score, the streak and the list of
/// today's drives.
@MainActor
final class TodayViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let loadFailureMessage = "No hemos podido cargar tu día. Desliza para reintentar."

    @Published private(set) var snapshot: TodaySnapshot = .empty

    @Published private(set) var isLoading = false

    @Published private(set) var errorMessage: String?

    private let snapshotLoader: TodaySnapshotLoader
    private let now: () -> Date

    init(
        dataLoader: TodayDataLoading = SupabaseTodayRepository(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.snapshotLoader = TodaySnapshotLoader(dataLoader: dataLoader, calendar: calendar)
        self.now = now
    }

    func load(userID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            snapshot = try await snapshotLoader.load(userID: userID, now: now())
        } catch {
            // A failed refresh must not blank the day the user is looking at: the
            // previous snapshot stays on screen next to the error.
            errorMessage = Self.loadFailureMessage
        }

        isLoading = false
    }
}
