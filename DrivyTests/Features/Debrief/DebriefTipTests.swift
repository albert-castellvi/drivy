import XCTest
@testable import Drivy

/// S2: the summary gives one piece of advice, chosen from the component that cost
/// the most points. The rule is pure and reads the weights the score charged, so
/// these tests pin the choice, the tie-break and the copy — including the promise
/// that no advice ever invites to drive more.
final class DebriefTipTests: XCTestCase {

    /// 2023-11-14T22:13:20Z
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(
        score: Int = 88,
        distanceKm: Double = 1.0,
        harshBrakes: Int = 0,
        harshAccelerations: Int = 0,
        phoneUseEvents: Int = 0,
        speedingEvents: Int = 0,
        connectedMode: Bool = false
    ) -> DriveRecord {
        let driveScore = DriveScore(
            score: score,
            distanceKm: distanceKm,
            durationSeconds: 100,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: connectedMode
        )
        return DriveRecord(score: driveScore, startedAt: Self.startedAt)
    }

    // MARK: - The component that cost the most

    func testACleanDriveGetsThePositiveAdvice() {
        XCTAssertEqual(DebriefTip.tip(for: makeRecord()), .clean)
        XCTAssertEqual(DebriefTip.clean.title, "Sin incidencias")
        XCTAssertEqual(
            DebriefTip.clean.message,
            "Nada que corregir: no has perdido puntos en este trayecto."
        )
    }

    func testBrakingCostsMoreThanAcceleration() {
        // 12 points per event per km against 8.
        let record = makeRecord(harshBrakes: 1, harshAccelerations: 1)

        XCTAssertEqual(DebriefTip.tip(for: record), .harshBrake)
    }

    func testSpeedingCostsMoreThanAcceleration() {
        // 10 against 8.
        let record = makeRecord(speedingEvents: 1, harshAccelerations: 1)

        XCTAssertEqual(DebriefTip.tip(for: record), .speeding)
    }

    func testEnoughAccelerationsOutweighOneBrake() {
        // 3 × 8 = 24 against 1 × 12.
        let record = makeRecord(harshBrakes: 1, harshAccelerations: 3)

        XCTAssertEqual(DebriefTip.tip(for: record), .harshAcceleration)
    }

    func testPhoneUseCostsTheMostButOnlyWhenItIsCharged() {
        // 25 against 2 × 12 = 24.
        let record = makeRecord(harshBrakes: 2, phoneUseEvents: 1)

        XCTAssertEqual(DebriefTip.tip(for: record), .phoneUse)
    }

    // MARK: - Fixed tie-break

    func testATieGoesToTheHeavierComponent() {
        // 2 × 12 = 24 and 3 × 8 = 24: the fixed order decides, not the counting.
        let record = makeRecord(harshBrakes: 2, harshAccelerations: 3)

        XCTAssertEqual(DebriefTip.tip(for: record), .harshBrake)
        XCTAssertEqual(DebriefTip.preferenceOrder, [.phoneUse, .harshBrake, .speeding, .harshAcceleration])
    }

    // MARK: - Connected driving (S13)

    func testConnectedModeNeverBlamesPhoneUse() {
        let record = makeRecord(phoneUseEvents: 5, connectedMode: true)

        XCTAssertEqual(DebriefTip.penalty(for: .phoneUse, in: record), 0)
        XCTAssertEqual(DebriefTip.tip(for: record), .clean)
    }

    func testConnectedModeStillAdvisesOnTheComponentThatCostPoints() {
        let record = makeRecord(harshBrakes: 1, phoneUseEvents: 4, connectedMode: true)

        XCTAssertEqual(DebriefTip.tip(for: record), .harshBrake)
    }

    // MARK: - Penalty arithmetic (S5 weights)

    func testPenaltyUsesTheWeightAndTheDistanceOfTheDrive() {
        let record = makeRecord(distanceKm: 2, harshBrakes: 1)

        // 1 event × 12 points per km / 2 km.
        XCTAssertEqual(DebriefTip.penalty(for: .harshBrake, in: record), 6, accuracy: 1e-9)
    }

    func testShortDriveUsesTheMinimumDistance() {
        let record = makeRecord(distanceKm: 0.05, harshBrakes: 1)

        // 12 / 0.1 (the engine's floor), not 12 / 0.05.
        XCTAssertEqual(DebriefTip.penalty(for: .harshBrake, in: record), 120, accuracy: 1e-9)
    }

    func testPenaltyOfACleanDriveIsZero() {
        let record = makeRecord()

        for tip in DebriefTip.allCases {
            XCTAssertEqual(DebriefTip.penalty(of: tip, in: record), 0)
        }
    }

    func testPenaltyOfTheTipMatchesThePenaltyOfItsKind() {
        let record = makeRecord(distanceKm: 4, speedingEvents: 2)

        XCTAssertEqual(
            DebriefTip.penalty(of: .speeding, in: record),
            DebriefTip.penalty(for: DriveEventKind.speeding, in: record)
        )
        XCTAssertEqual(
            DebriefTip.penalty(of: .speeding, in: record),
            Double(2) * ScoringRules.speedingPenaltyPerKm / 4,
            accuracy: 1e-9
        )
    }

    // MARK: - Copy

    func testEveryAdviceHasTitleMessageAndIcon() {
        for tip in DebriefTip.allCases {
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.message.isEmpty)
            XCTAssertFalse(tip.systemImage.isEmpty)
        }
    }

    func testNoAdviceEverInvitesToDriveMore() {
        // The whole feature exists to stop rewarding kilometres and drives (S2, S4).
        let forbidden = ["conduc", "km", "trayectos", "más rápido", "recorre"]
        for tip in DebriefTip.allCases {
            let copy = (tip.title + " " + tip.message).lowercased()
            for word in forbidden {
                XCTAssertFalse(copy.contains(word), "\(tip) mentions '\(word)': \(copy)")
            }
        }
    }
}
