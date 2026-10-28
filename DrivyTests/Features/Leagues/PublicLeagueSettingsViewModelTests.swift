import XCTest
@testable import Drivy

/// The Ajustes switch of the public leagues (S5): it reads the own entry and
/// writes the same opt-in the invitation card writes.
@MainActor
final class PublicLeagueSettingsViewModelTests: XCTestCase {

    private func makeSUT() -> (
        sut: PublicLeagueSettingsViewModel,
        fake: FakeLeaguesDataLoader
    ) {
        let fake = FakeLeaguesDataLoader()
        return (PublicLeagueSettingsViewModel(repository: fake), fake)
    }

    func testTheSwitchStartsOffWhenTheUserNeverDecided() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(nil)

        await sut.load()

        XCTAssertFalse(sut.isEnabled)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testTheSwitchFollowsTheStoredDecision() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 3, optedIn: true))

        await sut.load()

        XCTAssertTrue(sut.isEnabled)
    }

    func testTheSwitchIsOffAfterAnOptOut() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 3, optedIn: false))

        await sut.load()

        XCTAssertFalse(sut.isEnabled)
    }

    func testAFailedReadExplainsItself() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .failure(FakeLeaguesDataLoader.FakeError.network)

        await sut.load()

        XCTAssertFalse(sut.isEnabled)
        XCTAssertEqual(
            sut.errorMessage,
            PublicLeagueSettingsViewModel.loadFailureMessage
        )
    }

    func testTurningItOnStoresTheOptIn() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(nil)
        await sut.load()

        let saved = await sut.setEnabled(true)

        XCTAssertTrue(saved)
        XCTAssertEqual(fake.optInCalls, [true])
        XCTAssertTrue(sut.isEnabled)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isSaving)
    }

    func testTurningItOffStoresTheOptOut() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        await sut.load()

        let saved = await sut.setEnabled(false)

        XCTAssertTrue(saved)
        XCTAssertEqual(fake.optInCalls, [false])
        XCTAssertFalse(sut.isEnabled)
    }

    func testAFailedWriteSnapsTheSwitchBack() async {
        let (sut, fake) = makeSUT()
        fake.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        await sut.load()
        fake.setOptInError = FakeLeaguesDataLoader.FakeError.network

        let saved = await sut.setEnabled(false)

        XCTAssertFalse(saved)
        // The optimistic switch must not hide a write the backend refused.
        XCTAssertTrue(sut.isEnabled)
        XCTAssertEqual(
            sut.errorMessage,
            PublicLeagueSettingsViewModel.saveFailureMessage
        )
    }
}
