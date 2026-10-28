import XCTest
@testable import Drivy

/// The "Nombre visible" field of Ajustes (S2): it reads the stored name, validates
/// the edit with the server rule and only writes what the backend can keep.
@MainActor
final class DisplayNameViewModelTests: XCTestCase {

    private static let userID = "11111111-2222-3333-4444-555555555555"

    private func makeSUT() -> (
        sut: DisplayNameViewModel,
        fake: FakeProfileDataLoader
    ) {
        let fake = FakeProfileDataLoader()
        return (DisplayNameViewModel(repository: fake), fake)
    }

    // MARK: - Load

    func testTheStoredNameIsReadAndSeededIntoTheEditor() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")

        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.displayName, "Conductor 1234")
        XCTAssertEqual(sut.draft, "Conductor 1234")
        XCTAssertEqual(fake.displayNameCalls, [Self.userID])
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testTheNameStartsUnknown() {
        let (sut, _) = makeSUT()

        XCTAssertNil(sut.displayName)
        XCTAssertEqual(sut.draft, "")
    }

    func testAFailedReadExplainsItselfAndLeavesNoName() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .failure(FakeProfileDataLoader.FakeError.network)

        await sut.load(userID: Self.userID)

        XCTAssertNil(sut.displayName)
        XCTAssertEqual(sut.errorMessage, DisplayNameViewModel.loadFailureMessage)
        XCTAssertEqual(sut.errorMessage, "No hemos podido cargar tu nombre visible.")
        XCTAssertFalse(sut.isLoading)
    }

    /// The screen offers a retry when the name is unknown, so a read has to be
    /// repeatable after a failure.
    func testAReadCanBeRetriedAfterAFailure() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .failure(FakeProfileDataLoader.FakeError.network)
        await sut.load(userID: Self.userID)

        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)

        XCTAssertEqual(sut.displayName, "Conductor 1234")
        XCTAssertEqual(sut.draft, "Conductor 1234")
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(fake.displayNameCallCount, 2)
    }

    // MARK: - Validation

    func testAnEmptyDraftIsRejectedWithoutTouchingTheBackend() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)

        sut.draft = "   "
        let saved = await sut.save(userID: Self.userID)

        XCTAssertFalse(saved)
        XCTAssertTrue(fake.updateCalls.isEmpty)
        XCTAssertEqual(sut.errorMessage, DisplayNameRule.emptyMessage)
        // The stored name is untouched when the edit is refused.
        XCTAssertEqual(sut.displayName, "Conductor 1234")
    }

    func testATooLongDraftIsRejectedWithoutTouchingTheBackend() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)

        sut.draft = String(repeating: "a", count: DisplayNameRule.maxLength + 1)
        let saved = await sut.save(userID: Self.userID)

        XCTAssertFalse(saved)
        XCTAssertTrue(fake.updateCalls.isEmpty)
        XCTAssertEqual(sut.errorMessage, DisplayNameRule.tooLongMessage)
    }

    // MARK: - Save

    func testAValidDraftIsWrittenTrimmed() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)

        sut.draft = "  Ana Ruiz  "
        let saved = await sut.save(userID: Self.userID)

        XCTAssertTrue(saved)
        XCTAssertEqual(fake.updateCalls.count, 1)
        XCTAssertEqual(fake.updateCalls.first?.name, "Ana Ruiz")
        XCTAssertEqual(fake.updateCalls.first?.userID, Self.userID)
        XCTAssertEqual(sut.displayName, "Ana Ruiz")
        XCTAssertEqual(sut.draft, "Ana Ruiz")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isSaving)
    }

    func testTheLongestAllowedNameIsWritten() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)
        let name = String(repeating: "a", count: DisplayNameRule.maxLength)

        sut.draft = name
        let saved = await sut.save(userID: Self.userID)

        XCTAssertTrue(saved)
        XCTAssertEqual(fake.updateCalls.first?.name, name)
    }

    func testAFailedWriteKeepsTheStoredName() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)
        fake.updateError = FakeProfileDataLoader.FakeError.network

        sut.draft = "Ana Ruiz"
        let saved = await sut.save(userID: Self.userID)

        XCTAssertFalse(saved)
        XCTAssertEqual(sut.errorMessage, DisplayNameViewModel.saveFailureMessage)
        // A name the server refused must not be shown as the visible one.
        XCTAssertEqual(sut.displayName, "Conductor 1234")
        XCTAssertFalse(sut.isSaving)
    }

    // MARK: - Editor lifecycle

    func testResettingTheDraftGoesBackToTheStoredName() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)

        sut.draft = "Ana"
        sut.resetDraft()

        XCTAssertEqual(sut.draft, "Conductor 1234")
        XCTAssertNil(sut.errorMessage)
    }

    func testResettingForgetsTheValidationError() async {
        let (sut, fake) = makeSUT()
        fake.displayNameResult = .success("Conductor 1234")
        await sut.load(userID: Self.userID)
        sut.draft = "   "
        _ = await sut.save(userID: Self.userID)
        XCTAssertEqual(sut.errorMessage, DisplayNameRule.emptyMessage)

        sut.resetDraft()

        XCTAssertEqual(sut.draft, "Conductor 1234")
        XCTAssertNil(sut.errorMessage)
    }

    func testResettingWithoutANameLeavesAnEmptyDraft() {
        let (sut, _) = makeSUT()

        sut.draft = "Ana"
        sut.resetDraft()

        XCTAssertEqual(sut.draft, "")
    }
}
