import XCTest
@testable import Drivy

/// Divisions and movement copy of the public leagues (S5): "Bronce, Plata, Oro,
/// Platino, Diamante", seven promoted, five demoted, and the banner that
/// announces the last move.
final class PublicLeagueDivisionTests: XCTestCase {

    func testTheFiveDivisionsHaveTheirSpanishNames() {
        XCTAssertEqual(PublicLeagueDivision.name(for: 1), "Bronce")
        XCTAssertEqual(PublicLeagueDivision.name(for: 2), "Plata")
        XCTAssertEqual(PublicLeagueDivision.name(for: 3), "Oro")
        XCTAssertEqual(PublicLeagueDivision.name(for: 4), "Platino")
        XCTAssertEqual(PublicLeagueDivision.name(for: 5), "Diamante")
    }

    func testTheDivisionIsClampedToTheRangeTheServerAccepts() {
        XCTAssertEqual(PublicLeagueDivision.name(for: 0), "Bronce")
        XCTAssertEqual(PublicLeagueDivision.name(for: -3), "Bronce")
        XCTAssertEqual(PublicLeagueDivision.name(for: 6), "Diamante")
        XCTAssertEqual(PublicLeagueDivision.name(for: 99), "Diamante")

        XCTAssertEqual(PublicLeagueDivision.clamped(0), 1)
        XCTAssertEqual(PublicLeagueDivision.clamped(9), 5)
    }

    func testTheTitleNamesTheNumberOfTheDivisionAsWell() {
        XCTAssertEqual(PublicLeagueDivision.title(for: 2), "División 2 · Plata")
        XCTAssertEqual(PublicLeagueDivision.title(for: 0), "División 1 · Bronce")
    }

    func testTheBandsMapTheNumbersOfTheSpec() {
        // S5: 7 promote, 5 demote, groups of about 30.
        XCTAssertEqual(PublicLeagueDivision.promotionCount, 7)
        XCTAssertEqual(PublicLeagueDivision.demotionCount, 5)
        XCTAssertEqual(PublicLeagueDivision.maximumGroupSize, 30)
        XCTAssertEqual(PublicLeagueDivision.first, 1)
        XCTAssertEqual(PublicLeagueDivision.top, 5)
    }

    // MARK: - Banner of `last_change`

    func testAPromotionAnnouncesTheNewDivision() {
        let banner = PublicLeagueDivision.changeBanner(lastChange: 1, division: 2)

        XCTAssertEqual(banner, "Has subido a Plata.")
    }

    func testADemotionAnnouncesTheNewDivision() {
        let banner = PublicLeagueDivision.changeBanner(lastChange: -1, division: 1)

        XCTAssertEqual(banner, "Has bajado a Bronce.")
    }

    func testStayingKeepsTheSameDivisionInTheBanner() {
        let banner = PublicLeagueDivision.changeBanner(lastChange: 0, division: 3)

        XCTAssertEqual(banner, "Te mantienes en Oro.")
    }

    func testAnUnknownChangeIsReadAsStaying() {
        let banner = PublicLeagueDivision.changeBanner(lastChange: 7, division: 4)

        XCTAssertEqual(banner, "Te mantienes en Platino.")
    }

    // MARK: - Zone labels

    func testTheZonesHaveTheirLabels() {
        XCTAssertEqual(PublicLeagueZone.promotion.label, "Ascenso")
        XCTAssertEqual(PublicLeagueZone.demotion.label, "Descenso")
    }

    func testTheZoneExplanationsNameTheCountsOfTheSpec() {
        XCTAssertEqual(
            PublicLeagueZone.promotion.explanation,
            "Los 7 primeros suben de división el lunes."
        )
        XCTAssertEqual(
            PublicLeagueZone.demotion.explanation,
            "Los 5 últimos bajan de división el lunes."
        )
    }
}
