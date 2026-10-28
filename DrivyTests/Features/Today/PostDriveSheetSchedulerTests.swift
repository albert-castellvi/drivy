import XCTest
@testable import Drivy

/// S2/S9: the order of the sheets of the Hoy tab.
///
/// S2 asks for the post-drive summary "antes del paywall del primer trayecto" and S9
/// turns that paywall into a once-ever presentation: a finished drive opens its
/// debrief first, the paywall waits for it, and only the paywall consumes the gate.
final class PostDriveSheetSchedulerTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDrive(score: Int = 88, offset: TimeInterval = 0) -> DriveRecord {
        let driveScore = DriveScore(
            score: score,
            distanceKm: 12.5,
            durationSeconds: 900,
            harshBrakes: 0,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
        return DriveRecord(
            score: driveScore,
            startedAt: Self.startedAt.addingTimeInterval(offset)
        )
    }

    private func paywallState(
        hasCompletedDriveThisSession: Bool = true,
        wasPresented: Bool = false,
        isDue: Bool = true
    ) -> PostDriveSheetScheduler.PaywallState {
        PostDriveSheetScheduler.PaywallState(
            hasCompletedDriveThisSession: hasCompletedDriveThisSession,
            wasPresented: wasPresented,
            isDue: isDue
        )
    }

    // MARK: - S2: the debrief comes first

    func testAFinishedDriveOpensTheDebrief() {
        let drive = makeDrive()

        let step = PostDriveSheetScheduler.driveDidComplete(drive)

        XCTAssertEqual(step.nextSheet, TodaySheet.debrief(drive))
        XCTAssertFalse(step.consumesPaywallGate)
    }

    /// S2: the debrief never touches the S9 gate, so the paywall is still due right
    /// after it closes.
    func testTheDebriefAloneNeverConsumesThePaywallGate() {
        let step = PostDriveSheetScheduler.driveDidComplete(makeDrive())

        XCTAssertFalse(step.consumesPaywallGate)
        XCTAssertEqual(
            PostDriveSheetScheduler.paywallIfDue(shownSheet: nil, paywall: paywallState()).nextSheet,
            TodaySheet.paywall
        )
    }

    /// S2: two sheets cannot be on screen at once, so the paywall waits while the
    /// debrief of the same drive owns the slot.
    func testThePaywallWaitsWhileADebriefIsOnScreen() {
        let shown = TodaySheet.debrief(makeDrive())

        let step = PostDriveSheetScheduler.paywallIfDue(shownSheet: shown, paywall: paywallState())

        XCTAssertEqual(step, PostDriveSheetScheduler.Step.stay)
    }

    // MARK: - S9: the paywall of the first drive

    func testClosingTheDebriefOfTheFirstDriveOpensThePaywall() {
        let step = PostDriveSheetScheduler.paywallIfDue(shownSheet: nil, paywall: paywallState())

        XCTAssertEqual(step.nextSheet, TodaySheet.paywall)
        XCTAssertTrue(step.consumesPaywallGate)
    }

    /// S9: once ever. After the gate was used, the next drive opens its debrief and
    /// nothing else.
    func testASecondDriveAfterTheGateWasUsedOnlyOpensTheDebrief() {
        let second = makeDrive(score: 92, offset: 3600)
        let usedGate = paywallState(wasPresented: true, isDue: false)

        XCTAssertEqual(
            PostDriveSheetScheduler.driveDidComplete(second).nextSheet,
            TodaySheet.debrief(second)
        )
        XCTAssertEqual(
            PostDriveSheetScheduler.paywallIfDue(shownSheet: nil, paywall: usedGate),
            PostDriveSheetScheduler.Step.stay
        )
    }

    /// S9: a gate already presented never opens the paywall again, even if a caller
    /// hands over a state that still reads as due.
    func testThePaywallIsOnceEver() {
        let step = PostDriveSheetScheduler.paywallIfDue(
            shownSheet: nil,
            paywall: paywallState(wasPresented: true, isDue: true)
        )

        XCTAssertEqual(step, PostDriveSheetScheduler.Step.stay)
    }

    /// S9: only a drive finished in this session triggers the paywall. A plan that
    /// arrives later must not turn a launch into an ad for older drives.
    func testNoPaywallWithoutADriveFinishedInThisSession() {
        let step = PostDriveSheetScheduler.paywallIfDue(
            shownSheet: nil,
            paywall: paywallState(hasCompletedDriveThisSession: false)
        )

        XCTAssertEqual(step, PostDriveSheetScheduler.Step.stay)
    }

    /// S9/S8: on a plan that is not Free the S9 rule is not satisfied, so the debrief
    /// is the only sheet of the drive.
    func testAPaidPlanNeverOpensThePaywall() {
        let step = PostDriveSheetScheduler.paywallIfDue(
            shownSheet: nil,
            paywall: paywallState(isDue: false)
        )

        XCTAssertEqual(step, PostDriveSheetScheduler.Step.stay)
    }

    // MARK: - Identity of the sheets

    /// A second drive is a different sheet: `.sheet(item:)` presents it instead of
    /// keeping the debrief of the previous one.
    func testTwoDebriefsOfDifferentDrivesAreDifferentSheets() {
        let first = TodaySheet.debrief(makeDrive())
        let second = TodaySheet.debrief(makeDrive(score: 92, offset: 3600))

        XCTAssertNotEqual(first.id, second.id)
    }

    func testTheSheetsOfTheTabHaveDistinctIdentities() {
        let ids = [
            TodaySheet.shareCard.id,
            TodaySheet.paywall.id,
            TodaySheet.debrief(makeDrive()).id,
            TodaySheet.lesson.id
        ]

        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
