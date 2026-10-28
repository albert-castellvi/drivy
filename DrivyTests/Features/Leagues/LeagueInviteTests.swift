import XCTest
@testable import Drivy

/// S3: invite codes are validated against the alphabet the server draws them from,
/// and the invite link wraps one of them.
final class LeagueInviteTests: XCTestCase {

    /// 2023-11-14T00:00:00Z, a Tuesday.
    private static let tuesday = Date(timeIntervalSince1970: 1_699_920_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    // MARK: - Invite code

    /// S3: the code is drawn on the server (`public.create_league`), eight symbols
    /// of one alphabet. The client only normalizes and validates what it receives.
    func testAValidCodeIsEightSymbolsOfTheAlphabet() {
        XCTAssertEqual(LeagueInviteCode.length, 8)
        XCTAssertTrue(LeagueInviteCode.isValid("ABC23456"))
    }

    func testTheAlphabetLeavesOutTheConfusingGlyphs() {
        // The glyphs that get confused when a code is read aloud or from a
        // screenshot are not part of the alphabet at all.
        for confusing in ["I", "O", "0", "1"] {
            XCTAssertFalse(LeagueInviteCode.alphabet.contains(Character(confusing)))
        }
    }

    func testACodeOfTheWrongLengthIsRejected() {
        XCTAssertFalse(LeagueInviteCode.isValid("ABC2345"))
        XCTAssertFalse(LeagueInviteCode.isValid("ABC234567"))
        XCTAssertFalse(LeagueInviteCode.isValid(""))
    }

    /// A code outside the alphabet cannot exist, so it is refused before it spends
    /// one of the ten attempts the RPC allows per hour (S3).
    func testACodeWithASymbolOutsideTheAlphabetIsRejected() {
        XCTAssertFalse(LeagueInviteCode.isValid("ABC2345O"))
        XCTAssertFalse(LeagueInviteCode.isValid("ABC-3456"))
    }

    func testNormalizeAcceptsLowercaseAndSpaces() {
        XCTAssertEqual(LeagueInviteCode.normalize("  ab c23456 "), "ABC23456")
        XCTAssertTrue(LeagueInviteCode.isValid(LeagueInviteCode.normalize("  ab c23456 ")))
    }

    // MARK: - Invite link

    func testInviteLinkIsTheUniversalDeepLink() {
        XCTAssertEqual(
            LeagueInviteLink.url(forInviteCode: "abc23456")?.absoluteString,
            "https://drivy.app/l/ABC23456"
        )
    }

    func testEmptyCodeHasNoLink() {
        XCTAssertNil(LeagueInviteLink.url(forInviteCode: "   "))
    }

    func testInviteCodeIsExtractedFromTheLink() {
        let url = URL(string: "https://drivy.app/l/abc23456") ?? URL(fileURLWithPath: "/")

        XCTAssertEqual(LeagueInviteLink.inviteCode(from: url), "ABC23456")
    }

    func testForeignLinksAreRejected() {
        let url = URL(string: "https://example.com/l/ABC23456") ?? URL(fileURLWithPath: "/")

        XCTAssertNil(LeagueInviteLink.inviteCode(from: url))
    }

    func testUserInputAcceptsEitherABareCodeOrALink() {
        XCTAssertEqual(LeagueInviteLink.code(fromUserInput: "  abc23456 "), "ABC23456")
        XCTAssertEqual(
            LeagueInviteLink.code(fromUserInput: "https://drivy.app/l/ABC23456"),
            "ABC23456"
        )
    }

    // MARK: - Week start

    func testWeekStartsOnMonday() {
        let monday = WeekBounds.monday(for: Self.tuesday, calendar: utc)

        // 2023-11-13T00:00:00Z.
        XCTAssertEqual(monday, Date(timeIntervalSince1970: 1_699_833_600))
        XCTAssertEqual(WeekBounds.mondayKey(for: Self.tuesday, calendar: utc), "2023-11-13")
    }

    func testMondayIsItsOwnWeekStart() {
        let monday = Date(timeIntervalSince1970: 1_699_833_600)

        XCTAssertEqual(WeekBounds.monday(for: monday, calendar: utc), monday)
    }

    func testSundayBelongsToTheWeekThatStartedSixDaysBefore() {
        // 2023-11-19T00:00:00Z.
        let sunday = Date(timeIntervalSince1970: 1_700_352_000)

        XCTAssertEqual(WeekBounds.mondayKey(for: sunday, calendar: utc), "2023-11-13")
    }
}
