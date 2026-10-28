import XCTest
@testable import Drivy

/// Auth state machine, exercised without network and without the Apple sheet.
@MainActor
final class AuthViewModelTests: XCTestCase {

    private static let user = UserSummary(id: "11111111-2222-3333-4444-555555555555", email: "ana@example.com")
    private static let credential = AppleCredential(idToken: "apple-identity-token", rawNonce: "raw-nonce")

    // MARK: - Helpers

    private func makeSUT(
        restoredUser: UserSummary? = nil,
        signInOutcome: Result<UserSummary, Error> = .success(AuthViewModelTests.user)
    ) -> (
        sut: AuthViewModel,
        authService: FakeAuthService,
        appleProvider: FakeAppleSignInProvider,
        reporter: FakeCrashReporter
    ) {
        let authService = FakeAuthService()
        authService.restoredUser = restoredUser
        authService.signInOutcome = signInOutcome

        let appleProvider = FakeAppleSignInProvider()
        let reporter = FakeCrashReporter()
        let sut = AuthViewModel(
            authService: authService,
            appleSignInProvider: appleProvider,
            reportError: reporter.report,
            setReportedUser: reporter.setUser
        )
        return (sut, authService, appleProvider, reporter)
    }

    /// Starts a sign-in and waits until the Apple sheet is actually in flight.
    private func startSignIn(
        _ sut: AuthViewModel,
        _ appleProvider: FakeAppleSignInProvider
    ) async -> Task<Void, Never> {
        let started = expectation(description: "apple sheet started")
        appleProvider.onRequestStarted = { started.fulfill() }

        let task = Task { await sut.signInWithApple() }
        await fulfillment(of: [started], timeout: 2)
        return task
    }

    // MARK: - Restore

    func testStateStartsAsRestoring() {
        let (sut, _, _, _) = makeSUT()

        XCTAssertEqual(sut.state, .restoring)
        XCTAssertNil(sut.signedInUser)
    }

    func testRestoreSessionSignsInWhenASessionIsPersisted() async {
        let (sut, authService, _, _) = makeSUT(restoredUser: Self.user)

        await sut.restoreSession()

        XCTAssertEqual(authService.restoreCallCount, 1)
        XCTAssertEqual(sut.state, .signedIn(Self.user))
        XCTAssertEqual(sut.signedInUser, Self.user)
    }

    func testRestoreSessionSignsOutWhenThereIsNoSession() async {
        let (sut, _, _, _) = makeSUT(restoredUser: nil)

        await sut.restoreSession()

        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertNil(sut.signedInUser)
    }

    func testRestoreSessionRunsOnlyOnce() async {
        let (sut, authService, _, _) = makeSUT(restoredUser: Self.user)

        await sut.restoreSession()
        await sut.restoreSession()

        XCTAssertEqual(authService.restoreCallCount, 1)
        XCTAssertEqual(sut.state, .signedIn(Self.user))
    }

    // MARK: - Sign in with Apple

    func testSignInWithAppleSignsInAndForwardsTheCredential() async {
        let (sut, authService, appleProvider, _) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        XCTAssertEqual(sut.state, .authenticating)

        appleProvider.complete(with: Self.credential)
        await task.value

        XCTAssertEqual(appleProvider.requestCount, 1)
        XCTAssertEqual(authService.signInCallCount, 1)
        XCTAssertEqual(authService.lastIdToken, "apple-identity-token")
        XCTAssertEqual(authService.lastRawNonce, "raw-nonce")
        XCTAssertEqual(sut.state, .signedIn(Self.user))
    }

    func testSignInWithAppleCancellationReturnsToSignedOut() async {
        let (sut, authService, appleProvider, _) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.cancelled)
        await task.value

        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertEqual(authService.signInCallCount, 0)
    }

    func testSignInWithAppleFailureShowsTheExactMessage() async {
        let (sut, _, appleProvider, _) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.failed("boom"))
        await task.value

        XCTAssertEqual(sut.state, .failed(message: AuthViewModel.signInFailureMessage))
        XCTAssertEqual(sut.state, .failed(message: "No hemos podido iniciar sesión. Inténtalo de nuevo."))
        XCTAssertNil(sut.signedInUser)
    }

    func testSignInWithAppleFailsWhenTheTokenExchangeFails() async {
        let (sut, authService, appleProvider, _) = makeSUT(
            signInOutcome: .failure(FakeAuthService.FakeError.network)
        )
        let task = await startSignIn(sut, appleProvider)

        appleProvider.complete(with: Self.credential)
        await task.value

        XCTAssertEqual(authService.signInCallCount, 1)
        XCTAssertEqual(sut.state, .failed(message: AuthViewModel.signInFailureMessage))
        XCTAssertNil(sut.signedInUser)
    }

    func testSignInWithAppleIsIgnoredWhileAlreadyAuthenticating() async {
        let (sut, authService, appleProvider, _) = makeSUT()
        let firstRequest = await startSignIn(sut, appleProvider)

        await sut.signInWithApple()

        XCTAssertEqual(appleProvider.requestCount, 1)
        XCTAssertEqual(authService.signInCallCount, 0)
        XCTAssertEqual(sut.state, .authenticating)

        appleProvider.complete(with: Self.credential)
        await firstRequest.value

        XCTAssertEqual(authService.signInCallCount, 1)
        XCTAssertEqual(sut.state, .signedIn(Self.user))
    }

    // MARK: - Sign out

    func testSignOutClearsTheSession() async {
        let (sut, authService, _, _) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()

        await sut.signOut()

        XCTAssertEqual(authService.signOutCallCount, 1)
        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertNil(sut.signedInUser)
    }

    func testSignOutFailureShowsTheExactMessage() async {
        let (sut, authService, _, _) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()
        authService.signOutError = FakeAuthService.FakeError.network

        await sut.signOut()

        XCTAssertEqual(sut.state, .failed(message: AuthViewModel.signOutFailureMessage))
        XCTAssertEqual(sut.state, .failed(message: "No hemos podido cerrar sesión. Inténtalo de nuevo."))
    }

    // MARK: - Crash reporting (S4, S5)

    func testAppleFailureIsReportedAsASanitizedCode() async throws {
        let (sut, _, appleProvider, reporter) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.failed("boom"))
        await task.value

        XCTAssertEqual(reporter.reportedErrors.count, 1)
        XCTAssertEqual(reporter.reportedReports, [.appleSignInFailed])

        // S5: the sentence of the report is ours, not the one of the failure.
        let reported = try XCTUnwrap(reporter.reportedErrors.first)
        XCTAssertFalse(reported.localizedDescription.contains("boom"))
        // A failed sign-in must not claim a user.
        XCTAssertTrue(reporter.reportedUserIds.isEmpty)
    }

    func testTokenExchangeFailureIsReportedAsASanitizedCode() async {
        let (sut, _, appleProvider, reporter) = makeSUT(
            signInOutcome: .failure(FakeAuthService.FakeError.network)
        )
        let task = await startSignIn(sut, appleProvider)

        appleProvider.complete(with: Self.credential)
        await task.value

        XCTAssertEqual(reporter.reportedErrors.count, 1)
        XCTAssertEqual(reporter.reportedReports, [.authSignInFailed])
        // The `AuthError` behind the failure never reaches the reporter: its
        // description can embed the response body (S5).
        XCTAssertNil(reporter.reportedErrors.first as? FakeAuthService.FakeError)
        XCTAssertTrue(reporter.reportedUserIds.isEmpty)
    }

    /// A failure of the Apple sheet and a failure of the token exchange are told
    /// apart on the dashboard, but both are reported as codes (S5).
    func testTheTwoSignInFailuresReportDifferentCodes() async {
        let (appleSUT, _, appleProvider, appleReporter) = makeSUT()
        let appleTask = await startSignIn(appleSUT, appleProvider)
        appleProvider.fail(with: AppleSignInError.failed("boom"))
        await appleTask.value

        let (tokenSUT, _, tokenProvider, tokenReporter) = makeSUT(
            signInOutcome: .failure(FakeAuthService.FakeError.network)
        )
        let tokenTask = await startSignIn(tokenSUT, tokenProvider)
        tokenProvider.complete(with: Self.credential)
        await tokenTask.value

        XCTAssertEqual(appleReporter.reportedReports, [.appleSignInFailed])
        XCTAssertEqual(tokenReporter.reportedReports, [.authSignInFailed])
    }

    /// Cancelling the Apple sheet is the user's own decision, not a failure.
    func testSignInCancellationReportsNothing() async {
        let (sut, _, appleProvider, reporter) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.cancelled)
        await task.value

        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertTrue(reporter.reportedErrors.isEmpty)
        XCTAssertTrue(reporter.reportedUserIds.isEmpty)
    }

    func testSignInSetsTheReportedUserId() async {
        let (sut, _, appleProvider, reporter) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.complete(with: Self.credential)
        await task.value

        XCTAssertEqual(reporter.reportedUserIds, [Self.user.id])
        XCTAssertEqual(reporter.lastReportedUserId, Self.user.id)
    }

    func testRestoreSessionSetsTheReportedUserId() async {
        let (sut, _, _, reporter) = makeSUT(restoredUser: Self.user)

        await sut.restoreSession()

        XCTAssertEqual(reporter.reportedUserIds, [Self.user.id])
    }

    func testSignOutClearsTheReportedUserId() async {
        let (sut, _, _, reporter) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()

        await sut.signOut()

        // Set on restore, cleared on sign out: the second entry is an explicit nil.
        XCTAssertEqual(reporter.reportedUserIds, [Self.user.id, nil])
        XCTAssertNil(reporter.lastReportedUserId)
    }

    func testSignOutFailureIsReportedAsASanitizedCode() async {
        let (sut, authService, _, reporter) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()
        authService.signOutError = FakeAuthService.FakeError.network

        await sut.signOut()

        XCTAssertEqual(reporter.reportedErrors.count, 1)
        XCTAssertEqual(reporter.reportedReports, [.authSignOutFailed])
        XCTAssertNil(reporter.reportedErrors.first as? FakeAuthService.FakeError)
        // The session is still there, so the reported user is not cleared.
        XCTAssertEqual(reporter.reportedUserIds, [Self.user.id])
    }

    /// Reporting is a side channel: it must not change what the user reads.
    func testReportingDoesNotChangeTheFailureMessage() async {
        let (sut, _, appleProvider, reporter) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.failed("boom"))
        await task.value

        XCTAssertEqual(reporter.reportedErrors.count, 1)
        XCTAssertEqual(sut.state, .failed(message: "No hemos podido iniciar sesión. Inténtalo de nuevo."))
    }

    // MARK: - User summary

    func testUserSummaryShowsAShortIdentifier() {
        XCTAssertEqual(Self.user.shortIdentifier, "11111111")
    }
}
