import XCTest
@testable import Drivy

/// The rule of the visible name (S2), which mirrors the server CHECK constraint
/// `char_length(btrim(display_name)) between 1 and 30`.
final class DisplayNameRuleTests: XCTestCase {

    // MARK: - Trimming

    func testTheNameIsTrimmedBeforeItIsMeasured() {
        XCTAssertEqual(DisplayNameRule.normalized("  Ana Ruiz  "), "Ana Ruiz")
        XCTAssertEqual(DisplayNameRule.normalized("\nAna Ruiz\t"), "Ana Ruiz")
        XCTAssertEqual(DisplayNameRule.validate("  Ana Ruiz  "), .valid(name: "Ana Ruiz"))
    }

    func testTheSpacesInsideTheNameAreKept() {
        XCTAssertEqual(DisplayNameRule.validate(" Ana  Ruiz "), .valid(name: "Ana  Ruiz"))
    }

    // MARK: - Emptiness

    func testAnEmptyNameIsRejected() {
        XCTAssertEqual(DisplayNameRule.validate(""), .invalid(message: DisplayNameRule.emptyMessage))
        XCTAssertEqual(
            DisplayNameRule.validate(""),
            .invalid(message: "El nombre visible no puede estar vacío.")
        )
    }

    func testABlankNameIsRejected() {
        // `btrim` would leave nothing, so the server would reject it too.
        XCTAssertEqual(
            DisplayNameRule.validate("   \n\t "),
            .invalid(message: DisplayNameRule.emptyMessage)
        )
    }

    // MARK: - Length

    func testTheLongestAllowedNameIsAccepted() {
        let name = String(repeating: "a", count: DisplayNameRule.maxLength)

        XCTAssertEqual(DisplayNameRule.validate(name), .valid(name: name))
    }

    func testOneCharacterMoreIsRejected() {
        let name = String(repeating: "a", count: DisplayNameRule.maxLength + 1)

        XCTAssertEqual(
            DisplayNameRule.validate(name),
            .invalid(message: "El nombre visible no puede tener más de 30 caracteres.")
        )
    }

    func testTheLimitIsCountedLikeTheServerCountsIt() {
        // A grapheme cluster made of two scalars ("e" plus a combining accent) is
        // one character to the eye and two to `char_length`, so thirty of them do
        // not fit: the client has to reject what the CHECK constraint rejects.
        let name = String(repeating: "e\u{0301}", count: DisplayNameRule.maxLength)

        XCTAssertEqual(name.count, DisplayNameRule.maxLength)
        XCTAssertEqual(
            DisplayNameRule.validate(name),
            .invalid(message: DisplayNameRule.tooLongMessage)
        )
    }

    // MARK: - Copy

    func testTheMessagesAreTheOnesTheUserReads() {
        XCTAssertEqual(DisplayNameRule.emptyMessage, "El nombre visible no puede estar vacío.")
        XCTAssertEqual(
            DisplayNameRule.tooLongMessage,
            "El nombre visible no puede tener más de 30 caracteres."
        )
    }
}
