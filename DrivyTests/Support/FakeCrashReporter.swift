import Foundation
@testable import Drivy

/// Test double for the crash reporting boundary (S4): records what the app
/// wanted to send to Sentry, without a started SDK.
final class FakeCrashReporter {

    private(set) var reportedErrors: [Error] = []
    /// One entry per `setUser` call, in order. `nil` means "cleared".
    private(set) var reportedUserIds: [String?] = []

    func report(_ error: Error) {
        reportedErrors.append(error)
    }

    func setUser(_ id: String?) {
        reportedUserIds.append(id)
    }

    /// Last user id handed over, flattened out of the array's optional element.
    var lastReportedUserId: String? {
        guard let last = reportedUserIds.last else { return nil }
        return last
    }

    /// The reported failures that were already sanitized (S5). An entry of this
    /// array is a code with a fixed sentence; the raw error must be in
    /// `reportedErrors` and nowhere else.
    var reportedReports: [CrashReport] {
        reportedErrors.compactMap { $0 as? CrashReport }
    }
}
