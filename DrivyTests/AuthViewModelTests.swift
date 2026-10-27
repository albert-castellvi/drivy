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
    ) -> (sut: AuthViewModel, authService: FakeAuthService, appleProvider: FakeAppleSignInProvider) {
        let authService = FakeAuthService()
        authService.restoredUser = restoredUser
        authService.signInOutcome = signInOutcome

        let appleProvider = FakeAppleSignInProvider()
        let sut = AuthViewModel(authService: authService, appleSignInProvider: appleProvider)
        return (sut, authService, appleProvider)
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
        let (sut, _, _) = makeSUT()

        XCTAssertEqual(sut.state, .restoring)
        XCTAssertNil(sut.signedInUser)
    }

    func testRestoreSessionSignsInWhenASessionIsPersisted() async {
        let (sut, authService, _) = makeSUT(restoredUser: Self.user)

        await sut.restoreSession()

        XCTAssertEqual(authService.restoreCallCount, 1)
        XCTAssertEqual(sut.state, .signedIn(Self.user))
        XCTAssertEqual(sut.signedInUser, Self.user)
    }

    func testRestoreSessionSignsOutWhenThereIsNoSession() async {
        let (sut, _, _) = makeSUT(restoredUser: nil)

        await sut.restoreSession()

        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertNil(sut.signedInUser)
    }

    func testRestoreSessionRunsOnlyOnce() async {
        let (sut, authService, _) = makeSUT(restoredUser: Self.user)

        await sut.restoreSession()
        await sut.restoreSession()

        XCTAssertEqual(authService.restoreCallCount, 1)
        XCTAssertEqual(sut.state, .signedIn(Self.user))
    }

    // MARK: - Sign in with Apple

    func testSignInWithAppleSignsInAndForwardsTheCredential() async {
        let (sut, authService, appleProvider) = makeSUT()
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
        let (sut, authService, appleProvider) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.cancelled)
        await task.value

        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertEqual(authService.signInCallCount, 0)
    }

    func testSignInWithAppleFailureShowsTheExactMessage() async {
        let (sut, _, appleProvider) = makeSUT()
        let task = await startSignIn(sut, appleProvider)

        appleProvider.fail(with: AppleSignInError.failed("boom"))
        await task.value

        XCTAssertEqual(sut.state, .failed(message: AuthViewModel.signInFailureMessage))
        XCTAssertEqual(sut.state, .failed(message: "No hemos podido iniciar sesión. Inténtalo de nuevo."))
        XCTAssertNil(sut.signedInUser)
    }

    func testSignInWithAppleFailsWhenTheTokenExchangeFails() async {
        let (sut, authService, appleProvider) = makeSUT(
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
        let (sut, authService, appleProvider) = makeSUT()
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
        let (sut, authService, _) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()

        await sut.signOut()

        XCTAssertEqual(authService.signOutCallCount, 1)
        XCTAssertEqual(sut.state, .signedOut)
        XCTAssertNil(sut.signedInUser)
    }

    func testSignOutFailureShowsTheExactMessage() async {
        let (sut, authService, _) = makeSUT(restoredUser: Self.user)
        await sut.restoreSession()
        authService.signOutError = FakeAuthService.FakeError.network

        await sut.signOut()

        XCTAssertEqual(sut.state, .failed(message: AuthViewModel.signOutFailureMessage))
        XCTAssertEqual(sut.state, .failed(message: "No hemos podido cerrar sesión. Inténtalo de nuevo."))
    }

    // MARK: - User summary

    func testUserSummaryShowsAShortIdentifier() {
        XCTAssertEqual(Self.user.shortIdentifier, "11111111")
    }
}
