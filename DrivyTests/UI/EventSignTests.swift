import XCTest
@testable import Drivy

/// S3: one vocabulary for the drive events, shared by the debrief, the map markers
/// and the history rows — a harsh brake is a warning triangle everywhere, the phone
/// is a prohibition disc, speeding is a speed-limit disc.
final class EventSignTests: XCTestCase {

    /// The sign S3 fixes for each event kind, keyed by its stable `rawValue`.
    private static var expected: [(rawValue: String, kind: RoadSign.Kind)] {
        [
            ("harshBrake", .warning(systemName: "exclamationmark")),
            ("harshAcceleration", .warning(systemName: "exclamationmark")),
            ("phoneUse", .prohibition(systemName: "iphone")),
            ("speeding", .speedLimit(50))
        ]
    }

    // MARK: - Every kind

    func testEveryEventKindWearsTheSignOfTheDesignSystem() {
        for kind in DriveEventKind.allCases {
            guard let expectation = Self.expected.first(where: { $0.rawValue == kind.rawValue }) else {
                XCTFail("event kind \"\(kind.rawValue)\" has no expected sign")
                continue
            }

            XCTAssertEqual(
                EventSign.sign(for: kind),
                expectation.kind,
                "event kind \"\(kind.rawValue)\" wears the wrong sign"
            )
        }
    }

    /// No kind of the scoring engine may be left without a sign.
    func testEveryEventKindHasAnExpectation() {
        XCTAssertEqual(
            Self.expected.count,
            DriveEventKind.allCases.count,
            "every case of DriveEventKind needs one expectation"
        )
    }

    func testEveryExpectationBelongsToARealEventKind() {
        let rawValues = DriveEventKind.allCases.map { $0.rawValue }

        for expectation in Self.expected {
            XCTAssertTrue(
                rawValues.contains(expectation.rawValue),
                "expectation \"\(expectation.rawValue)\" is not a DriveEventKind"
            )
        }
    }

    // MARK: - The signs that carry a rule of their own

    /// A harsh brake and a harsh acceleration are the same warning: something to
    /// watch for on the next drive.
    func testHarshBrakeAndHarshAccelerationShareTheWarningTriangle() {
        XCTAssertEqual(
            EventSign.sign(for: .harshBrake),
            .warning(systemName: "exclamationmark")
        )
        XCTAssertEqual(
            EventSign.sign(for: .harshAcceleration),
            .warning(systemName: "exclamationmark")
        )
    }

    func testPhoneUseIsAProhibitionDiscWithThePhone() {
        XCTAssertEqual(EventSign.sign(for: .phoneUse), .prohibition(systemName: "iphone"))
    }

    func testSpeedingIsASpeedLimitDisc() {
        XCTAssertEqual(EventSign.sign(for: .speeding), .speedLimit(50))
    }
}
