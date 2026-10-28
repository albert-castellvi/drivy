import XCTest
@testable import Drivy

/// The daily quest board (S6): deterministic from the user and the day, three
/// quests, and always one that needs no driving.
final class DailyQuestBoardTests: XCTestCase {

    private let userID = "11111111-2222-3333-4444-555555555555"

    private func dayKey(_ offset: Int, from start: String = "2026-03-01") -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: start) else { return start }
        let shifted = calendar.date(byAdding: .day, value: offset, to: date) ?? date
        return formatter.string(from: shifted)
    }

    private func board(day offset: Int, userID: String? = nil) -> [DailyQuest] {
        DailyQuestBoard.quests(for: userID ?? self.userID, dayKey: dayKey(offset))
    }

    /// The same day has to show the same quests on every launch: `hashValue` is
    /// seeded per process, the board must not be.
    func testTheBoardIsDeterministic() {
        XCTAssertEqual(board(day: 0).map(\.id), board(day: 0).map(\.id))
        XCTAssertEqual(
            DailyQuestBoard.quests(for: userID, dayKey: dayKey(0)).map(\.id),
            DailyQuestBoard.quests(for: userID, dayKey: dayKey(0)).map(\.id)
        )
    }

    func testTheBoardHasThreeDifferentQuestsFromTheCatalog() {
        for offset in 0..<40 {
            let quests = board(day: offset)
            let ids = quests.map(\.id)

            XCTAssertEqual(quests.count, DailyQuestBoard.dailyCount)
            XCTAssertEqual(Set(ids).count, quests.count, "duplicate quest on day \(offset)")
            for id in ids {
                XCTAssertTrue(QuestCatalog.all.contains { $0.id == id }, "\(id) is not in the catalog")
            }
        }
    }

    /// S6: "siempre al menos una que se pueda completar sin conducir".
    func testEveryDayHasAQuestWithoutDriving() {
        for offset in 0..<60 {
            let quests = board(day: offset)

            XCTAssertTrue(
                quests.contains { !$0.requirement.needsDriving },
                "no quest without driving on day \(offset)"
            )
        }
    }

    /// The board rotates: a month of days does not repeat the same three quests.
    func testTheBoardRotatesAcrossDays() {
        let boards = Set((0..<30).map { board(day: $0).map(\.id).joined(separator: ",") })

        XCTAssertGreaterThan(boards.count, 1)
    }

    func testTwoUsersDoNotShareTheSameBoardEveryDay() {
        let mine = (0..<30).map { board(day: $0, userID: userID).map(\.id).joined(separator: ",") }
        let theirs = (0..<30).map {
            board(day: $0, userID: "99999999-8888-7777-6666-555555555555").map(\.id).joined(separator: ",")
        }

        XCTAssertNotEqual(mine, theirs)
    }

    func testASmallCatalogIsReturnedWhole() {
        let small = [
            QuestCatalog.lesson,
            DailyQuest(id: "clean_drive", title: "", detail: "", requirement: .cleanDrive(minimumScore: 90))
        ]

        let quests = DailyQuestBoard.quests(for: userID, dayKey: dayKey(0), catalog: small)

        XCTAssertEqual(Set(quests.map(\.id)), Set(small.map(\.id)))
    }

    /// FNV-1a is fixed, unlike `hashValue`: the same string always hashes the same.
    func testStableHashIsReproducible() {
        XCTAssertEqual(DailyQuestBoard.stableHash("drivy"), DailyQuestBoard.stableHash("drivy"))
        XCTAssertNotEqual(DailyQuestBoard.stableHash("drivy"), DailyQuestBoard.stableHash("drivz"))
    }
}
