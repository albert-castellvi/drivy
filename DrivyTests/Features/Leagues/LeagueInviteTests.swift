import XCTest
@testable import Drivy

/// S7: invite code, universal invite link and the Monday-based week the ranking
/// RPC is called with.
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

    func testGeneratedCodeUsesTheSafeAlphabet() {
        let code = LeagueInviteCode.generate()

        XCTAssertEqual(code.count, LeagueInviteCode.length)
        XCTAssertTrue(code.allSatisfy { LeagueInviteCode.alphabet.contains($0) })

        // The glyphs that get confused when a code is read aloud or from a
        // screenshot are not part of the alphabet at all.
        for confusing in ["I", "O", "0", "1"] {
            XCTAssertFalse(code.contains(Character(confusing)))
        }
    }

    func testGenerateIsDeterministicWithInjectedRandomness() {
        var next = -1
        let code = LeagueInviteCode.generate { _ in
            next += 1
            return next
        }

        XCTAssertEqual(code, "ABCDEF")
    }

    func testNormalizeAcceptsLowercaseAndSpaces() {
        XCTAssertEqual(LeagueInviteCode.normalize("  ab c234 "), "ABC234")
    }

    // MARK: - Invite link

    func testInviteLinkIsTheUniversalDeepLink() {
        XCTAssertEqual(
            LeagueInviteLink.url(forInviteCode: "abc234")?.absoluteString,
            "https://drivy.app/l/ABC234"
        )
    }

    func testEmptyCodeHasNoLink() {
        XCTAssertNil(LeagueInviteLink.url(forInviteCode: "   "))
    }

    func testInviteCodeIsExtractedFromTheLink() {
        let url = URL(string: "https://drivy.app/l/abc234") ?? URL(fileURLWithPath: "/")

        XCTAssertEqual(LeagueInviteLink.inviteCode(from: url), "ABC234")
    }

    func testForeignLinksAreRejected() {
        let url = URL(string: "https://example.com/l/ABC234") ?? URL(fileURLWithPath: "/")

        XCTAssertNil(LeagueInviteLink.inviteCode(from: url))
    }

    func testUserInputAcceptsEitherABareCodeOrALink() {
        XCTAssertEqual(LeagueInviteLink.code(fromUserInput: "  abc234 "), "ABC234")
        XCTAssertEqual(
            LeagueInviteLink.code(fromUserInput: "https://drivy.app/l/ABC234"),
            "ABC234"
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
