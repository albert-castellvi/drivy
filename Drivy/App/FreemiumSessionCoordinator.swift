import Combine
import Foundation

/// Owns the freemium service of the signed-in session (S9).
///
/// The plan belongs to the session, not to the app: the service is created when a
/// user signs in (anchored at the account creation date read from the auth
/// session), read once, kept in sync with StoreKit, and dropped on sign-out so a
/// second account on the same device never inherits the previous plan or the
/// previous history window.
///
/// Everything StoreKit-related stays behind `PremiumEntitlementProviding`, so the
/// whole lifecycle is asserted in unit tests with a fake (`makeService` is
/// injected too).
@MainActor
final class FreemiumSessionCoordinator: ObservableObject {

    /// Prefix of the persisted first-drive anchor, one value per account (see
    /// `recordCompletedDrive`). It has to survive launches: the anchor is part of the
    /// S9 window, not of a single run of the app.
    static let firstDriveAnchorKeyPrefix = "drivy.freemium.firstDriveAnchor."

    /// Service of the current session; `nil` while signed out.
    @Published private(set) var service: FreemiumService?

    private let makeService: @MainActor (Date) -> FreemiumService
    private let defaults: UserDefaults
    private let now: () -> Date
    private var signedInUserID: String?

    /// - Parameters:
    ///   - makeService: builds the session service from its anchor date. The
    ///     default is the real one (StoreKit behind `PremiumEntitlementProviding`);
    ///     tests inject a fake.
    ///   - defaults: storage of the per-account first-drive anchor.
    ///   - now: clock, injectable for the anchor fallback and for tests.
    init(
        makeService: @escaping @MainActor (Date) -> FreemiumService = {
            FreemiumService(anchorDate: $0)
        },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.makeService = makeService
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Session

    /// Creates the session's service anchored at `auth.users.created_at` (S9),
    /// reads the plan and subscribes to StoreKit updates.
    ///
    /// Falling back to `now()` only when the session carries no creation date keeps
    /// the window conservative instead of throwing the gate away.
    func signIn(as user: UserSummary) async {
        if signedInUserID != user.id {
            // A different account starts from a clean service.
            service?.stopObservingEntitlementUpdates()
            service = makeService(anchorDate(for: user))
            signedInUserID = user.id
        }

        guard let service else { return }

        await service.refresh()
        service.startObservingEntitlementUpdates()
    }

    /// Ends the session: the StoreKit listener is cancelled and the service (with
    /// its plan and gating snapshot) is dropped.
    func signOut() {
        service?.stopObservingEntitlementUpdates()
        service = nil
        signedInUserID = nil
    }

    // MARK: - Anchor of the free window

    /// L10: the 7-day window starts at the account creation date, but a profile can
    /// be much older than the first drive, so it moves to the first drive date.
    ///
    /// It happens once per account: re-anchoring on every drive would slide the
    /// window forward forever and a free account would never lose the full history.
    func recordCompletedDrive(startedAt: Date) {
        guard let service, let userID = signedInUserID else { return }

        let key = Self.firstDriveAnchorKeyPrefix + userID
        guard storedAnchor(forKey: key) == nil else { return }

        defaults.set(startedAt.timeIntervalSince1970, forKey: key)
        service.updateAnchorDate(startedAt)
    }

    /// Anchor of the S9 window: the account creation date, or the stored first-drive
    /// date when it is later (a profile can be older than its first drive).
    private func anchorDate(for user: UserSummary) -> Date {
        let accountCreatedAt = user.createdAt ?? now()
        guard let firstDrive = storedAnchor(forKey: Self.firstDriveAnchorKeyPrefix + user.id) else {
            return accountCreatedAt
        }
        return max(accountCreatedAt, firstDrive)
    }

    private func storedAnchor(forKey key: String) -> Date? {
        guard let interval = defaults.object(forKey: key) as? Double else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}
