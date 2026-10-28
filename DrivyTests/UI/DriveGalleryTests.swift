import CoreLocation
import SwiftUI
import XCTest
@testable import Drivy

/// S8 for T3: the visual proof of the debrief, the drive detail and the share
/// card, and the tests of the three pure presentation helpers those screens now
/// read (the lamp/list rows of a stored drive, the sign of the advice block, and
/// the signals the printed card is allowed to claim).
///
/// The maps render blank through `ImageRenderer` (S8, known and accepted); the
/// galleries still prove the layout around them, the lamps, the signs and the card.
@MainActor
final class DriveGalleryTests: XCTestCase {

    // MARK: - Gallery (S8)

    /// A clean drive: no events at all, so every lamp is unlit and the list shows
    /// four zeroes. The screen must still look finished, not broken.
    func testDebriefWithoutEventsRendersInLightAndDark() {
        let startedAt = Self.date(secondsSinceReference: 7_000_000_000)
        storeRoute(for: startedAt, points: 6)

        renderGallery("debrief-clean") {
            DriveDebriefView(record: Self.cleanRecord(startedAt: startedAt), onClose: {})
        }
    }

    /// One harsh brake (with its position) and one phone use (without, exactly as
    /// the engine reports it): one sign on the map, two lit lamps.
    func testDebriefWithEventsRendersInLightAndDark() {
        let startedAt = Self.date(secondsSinceReference: 7_000_000_100)
        storeRoute(for: startedAt, points: 6)

        renderGallery("debrief-events") {
            DriveDebriefView(record: Self.eventedRecord(startedAt: startedAt), onClose: {})
        }
    }

    /// The detail of a stored drive, with the route this device still remembers.
    func testDriveDetailRendersInLightAndDark() {
        let startedAt = Self.date(secondsSinceReference: 7_000_000_200)
        storeRoute(for: startedAt, points: 8)

        renderGallery("drive-detail") {
            NavigationStack {
                DriveDetailView(drive: Self.mixedDrive(startedAt: startedAt))
            }
        }
    }

    /// The card at its native size. `renderGallery` draws it twice: the dark PNG
    /// is the proof that the printed card ignores the system appearance (S6).
    func testShareCardRendersInLightAndDark() {
        let side = ShareCardView.side

        renderGallery("share-card", width: side, height: side) {
            ShareCardView(
                model: ShareCardModel(
                    score: 87,
                    streakDays: 3,
                    leaguePosition: 2,
                    leagueName: "Los del barrio",
                    leagueSize: 4,
                    divisionName: "Plata"
                )
            )
        }
    }

    /// The other end of the card: a day with nothing to claim. It must still be a
    /// finished picture, with the score post and no sign at all.
    func testShareCardWithoutFactsRendersInLightAndDark() {
        let side = ShareCardView.side

        renderGallery("share-card-bare", width: side, height: side) {
            ShareCardView(
                model: ShareCardModel(
                    score: 61,
                    streakDays: 0,
                    leaguePosition: nil,
                    leagueName: nil,
                    leagueSize: 0
                )
            )
        }
    }

    // MARK: - The rows a stored drive publishes (S5)

    func testEventRowsOfAStoredDriveCoverEveryKindInOrder() {
        let drive = Self.mixedDrive(startedAt: Self.date(secondsSinceReference: 7_000_000_300))

        XCTAssertEqual(drive.eventRows.map(\.kind), DriveEventKind.allCases)
        XCTAssertEqual(drive.eventRows.map(\.id), DriveEventKind.allCases.map(\.rawValue))
        XCTAssertEqual(
            drive.eventRows.map(\.count),
            [drive.harshBrakes, drive.harshAccelerations, drive.speedingEvents, drive.phoneUseEvents]
        )
    }

    /// The lamps read their lit state from the same counts, so a drive that cost
    /// nothing cannot light a lamp, and a drive with events cannot leave one dark.
    func testLitLampsAreExactlyTheKindsThatHappened() {
        let clean = Self.cleanDrive(startedAt: Self.date(secondsSinceReference: 7_000_000_400))
        XCTAssertEqual(clean.eventRows.filter { $0.count > 0 }.map(\.kind), [])

        let mixed = Self.mixedDrive(startedAt: Self.date(secondsSinceReference: 7_000_000_500))
        XCTAssertEqual(
            mixed.eventRows.filter { $0.count > 0 }.map(\.kind),
            [.harshBrake, .harshAcceleration, .speeding]
        )
    }

    /// The debrief and the detail of one drive cannot disagree: same order, same
    /// counts, same words.
    func testDebriefAndDetailPublishTheSameRowsForTheSameDrive() {
        let drive = Self.mixedDrive(startedAt: Self.date(secondsSinceReference: 7_000_000_600))
        let summary = DebriefSummary(record: Self.record(for: drive))

        XCTAssertEqual(summary.eventRows, drive.eventRows)
        XCTAssertEqual(
            summary.eventRows.map(\.kind.debriefTitle),
            ["Frenadas bruscas", "Aceleraciones bruscas", "Excesos de velocidad", "Uso del móvil"]
        )
    }

    // MARK: - The sign of the advice block (S3, S5)

    /// An advice is information, never a hazard painted on the road: the block
    /// always wears the blue face, in every one of its cases.
    func testEveryAdviceWearsTheBlueInformationFace() {
        for tip in DebriefTip.allCases {
            guard case .info = tip.infoSign else {
                XCTFail("El consejo \(tip.title) no lleva un panel de información: \(tip.infoSign)")
                continue
            }
        }

        XCTAssertEqual(DebriefTip.clean.infoSign, .info(systemName: "checkmark"))
        XCTAssertEqual(DebriefTip.harshBrake.infoSign, .info(systemName: "hand.raised.fill"))
        XCTAssertEqual(DebriefTip.phoneUse.infoSign, .info(systemName: "iphone"))
        XCTAssertEqual(
            DebriefTip.speeding.infoSign,
            .info(systemName: "speedometer")
        )
        XCTAssertEqual(
            DebriefTip.harshAcceleration.infoSign,
            .info(systemName: "arrow.up.right")
        )
    }

    // MARK: - What the printed card may claim (S6)

    /// A card with no streak, no division and no position prints no signal at all:
    /// an absence is never dressed up as an achievement.
    func testCardWithoutFactsPrintsNoSignal() {
        XCTAssertEqual(ShareCardSignals.signals(for: .empty), [])
    }

    /// The card only ever prints the words the model already produces, in the order
    /// the card has always read them. It invents no claim about events it cannot
    /// see: `ShareCardModel` carries no event counts.
    func testCardSignalsOnlyPrintTheModelsOwnWords() {
        let model = ShareCardModel(
            score: 87,
            streakDays: 3,
            leaguePosition: 2,
            leagueName: "Los del barrio",
            leagueSize: 4,
            divisionName: "Plata"
        )

        XCTAssertEqual(
            ShareCardSignals.signals(for: model).map(\.caption),
            [model.streakText, model.divisionText ?? "", model.leagueText]
        )

        let everyCaptionIsModelCopy: (ShareCardModel) -> Bool = { candidate in
            let own = [candidate.streakText, candidate.divisionText, candidate.leagueText]
            return ShareCardSignals.signals(for: candidate).allSatisfy { signal in
                own.contains(signal.caption)
            }
        }
        XCTAssertTrue(everyCaptionIsModelCopy(model))
        XCTAssertTrue(
            everyCaptionIsModelCopy(
                ShareCardModel(score: 40, streakDays: 1, leaguePosition: nil, leagueName: nil, leagueSize: 0)
            )
        )
    }

    /// A day that is not a streak day does not print "Sin racha" as a signal.
    func testCardNeverPrintsAnEmptyStreakAsASignal() {
        let model = ShareCardModel(
            score: 87,
            streakDays: 0,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0
        )

        XCTAssertEqual(ShareCardSignals.signals(for: model), [])
    }

    /// The absence of a league keeps its line on the card — the same line, and in
    /// the same cases, the screen has always printed and `accessibilitySummary`
    /// still describes — but it never becomes a sign.
    func testQuietLineOfTheCardFollowsTheModelsOwnLeagueRule() {
        let noLeagueAtAll = ShareCardModel(
            score: 61,
            streakDays: 0,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0
        )
        XCTAssertEqual(ShareCardSignals.quietLine(for: noLeagueAtAll), noLeagueAtAll.leagueText)
        XCTAssertTrue(ShareCardSignals.signals(for: noLeagueAtAll).isEmpty)

        let divisionWithoutPosition = ShareCardModel(
            score: 61,
            streakDays: 0,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0,
            divisionName: "Plata"
        )
        XCTAssertNil(ShareCardSignals.quietLine(for: divisionWithoutPosition))

        let withPosition = ShareCardModel(
            score: 61,
            streakDays: 0,
            leaguePosition: 3,
            leagueName: nil,
            leagueSize: 8
        )
        XCTAssertNil(ShareCardSignals.quietLine(for: withPosition))
    }

    /// With a public division and no weekly position, the private-league line is
    /// the model's own noise rule (`showsLeagueLine`), and the card follows it.
    func testCardPrintsTheLeagueOnlyWhenThereIsAPositionOrNoDivision() {
        let divisionWithoutPosition = ShareCardModel(
            score: 87,
            streakDays: 0,
            leaguePosition: nil,
            leagueName: nil,
            leagueSize: 0,
            divisionName: "Plata"
        )
        XCTAssertEqual(
            ShareCardSignals.signals(for: divisionWithoutPosition).map(\.caption),
            [divisionWithoutPosition.divisionText ?? ""]
        )

        let privateLeagueOnly = ShareCardModel(
            score: 87,
            streakDays: 0,
            leaguePosition: 4,
            leagueName: "Los del barrio",
            leagueSize: 8
        )
        XCTAssertEqual(
            ShareCardSignals.signals(for: privateLeagueOnly).map(\.caption),
            [privateLeagueOnly.leagueText]
        )
    }

    // MARK: - Fixtures

    /// A start time of its own for every fixture: the route store is a process-wide
    /// singleton, so two screens must never look up the same drive.
    private static func date(secondsSinceReference: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: secondsSinceReference)
    }

    /// The route `LocalRouteStore` would hold for a drive recorded on this device.
    private func storeRoute(for startedAt: Date, points: Int) {
        let coordinates: [CLLocationCoordinate2D] = (0..<points).map { index in
            let step = Double(index) * 0.0012
            return CLLocationCoordinate2D(latitude: 41.3874 + step, longitude: 2.1686 + step)
        }
        LocalRouteStore.shared.store(DriveTrack(coordinates: coordinates), forStartedAt: startedAt)
    }

    /// A drive with nothing to correct: every count zero, no events.
    private static func cleanRecord(startedAt: Date) -> DriveRecord {
        DriveRecord(
            score: DriveScore(
                score: 95,
                distanceKm: 3.2,
                durationSeconds: 600,
                harshBrakes: 0,
                harshAccelerations: 0,
                phoneUseEvents: 0,
                speedingEvents: 0,
                connectedMode: true,
                events: []
            ),
            startedAt: startedAt
        )
    }

    /// One harsh brake at a known point, one phone use with no point in the route
    /// (S5: phone use is a drive-level fact).
    private static func eventedRecord(startedAt: Date) -> DriveRecord {
        DriveRecord(
            score: DriveScore(
                score: 74,
                distanceKm: 4.8,
                durationSeconds: 660,
                harshBrakes: 1,
                harshAccelerations: 0,
                phoneUseEvents: 1,
                speedingEvents: 0,
                connectedMode: false,
                events: [
                    DriveEvent(
                        kind: .harshBrake,
                        timestamp: 240,
                        coordinate: DriveCoordinate(latitude: 41.3882, longitude: 2.1694)
                    ),
                    DriveEvent(kind: .phoneUse)
                ]
            ),
            startedAt: startedAt
        )
    }

    private static func cleanDrive(startedAt: Date) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "gallery-clean",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceKm: 3.2,
            durationSeconds: 600,
            score: 95,
            harshBrakes: 0,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: true
        )
    }

    private static func mixedDrive(startedAt: Date) -> DriveHistoryRow {
        DriveHistoryRow(
            id: "gallery-mixed",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(900),
            distanceKm: 12.3,
            durationSeconds: 900,
            score: 87,
            harshBrakes: 2,
            harshAccelerations: 1,
            phoneUseEvents: 0,
            speedingEvents: 3,
            connectedMode: true
        )
    }

    /// The same drive in the two shapes the two screens read: the row the server
    /// returned, and the record this device still holds.
    private static func record(for drive: DriveHistoryRow) -> DriveRecord {
        DriveRecord(
            score: DriveScore(
                score: drive.score,
                distanceKm: drive.distanceKm,
                durationSeconds: TimeInterval(drive.durationSeconds),
                harshBrakes: drive.harshBrakes,
                harshAccelerations: drive.harshAccelerations,
                phoneUseEvents: drive.phoneUseEvents,
                speedingEvents: drive.speedingEvents,
                connectedMode: drive.connectedMode,
                events: []
            ),
            startedAt: drive.startedAt
        )
    }
}
