import XCTest
@testable import Drivy

/// S9 history gating: a free account keeps the full history for 7 days and then only
/// the last day; the Histórico screen turns the hidden days into one upsell row with
/// the exact copy of `PaywallCopy`.
///
/// `FreemiumAccess` is built directly, so the rules are asserted without StoreKit and
/// without a clock.
final class HistoryGatingTests: XCTestCase {

    /// Sunday 2026-03-01 09:00 UTC: the anchor of the free window.
    private static let anchorDate = PremiumFixtures.anchorDate

    private func access(plan: FreemiumPlan, daysSinceAnchor: Int) -> FreemiumAccess {
        FreemiumAccess(
            plan: plan,
            anchorDate: Self.anchorDate,
            now: PremiumFixtures.date(anchorOffsetDays: daysSinceAnchor),
            calendar: PremiumFixtures.calendar
        )
    }

    /// Days newest first, like `public.daily_scores` returns them: day `offset` of the
    /// window, 14 … 0 days after the anchor.
    private func days(count: Int, daysSinceAnchor: Int) -> [HistoryDay] {
        (0..<count).map { index in
            let offset = daysSinceAnchor - index
            let date = PremiumFixtures.date(anchorOffsetDays: offset)
            return HistoryDay(
                dayKey: "day-\(offset)",
                date: date,
                score: 90 - index,
                distanceKm: 10,
                drivesCount: 1
            )
        }
    }

    // MARK: - Unknown plan

    func testAnUnknownPlanHidesNothing() {
        let rows = HistoryGating.rows(days: days(count: 3, daysSinceAnchor: 10), access: nil)

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { if case .day = $0 { return true } else { return false } })
    }

    // MARK: - Free plan inside the window

    func testAFreeAccountSeesEveryDayInsideTheGraceWindow() {
        // Day 1 to day 7 after the anchor are full history (S9).
        let rows = HistoryGating.rows(
            days: days(count: 5, daysSinceAnchor: 6),
            access: access(plan: .free, daysSinceAnchor: 6)
        )

        XCTAssertEqual(rows.count, 5)
        XCTAssertFalse(rows.contains { if case .locked = $0 { return true } else { return false } })
    }

    // MARK: - Free plan after the window

    func testAFreeAccountOnlySeesTheLastDayAfterTheWindow() {
        let allDays = days(count: 5, daysSinceAnchor: 10)

        let rows = HistoryGating.rows(
            days: allDays,
            access: access(plan: .free, daysSinceAnchor: 10)
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first, .day(allDays[0]))
        // The four older days are collapsed into one upsell row, not four.
        XCTAssertEqual(rows.last, .locked(hiddenDayCount: 4))
    }

    func testTheLockedRowUsesThePaywallCopy() {
        let rows = HistoryGating.rows(
            days: days(count: 3, daysSinceAnchor: 10),
            access: access(plan: .free, daysSinceAnchor: 10)
        )

        XCTAssertTrue(rows.contains(.locked(hiddenDayCount: 2)))
        XCTAssertEqual(HistoryGating.lockedMessage, PaywallCopy.historyLockedMessage)
        XCTAssertEqual(
            HistoryGating.lockedMessage,
            "Con el plan Free solo ves el día de hoy. Hazte Premium para ver todo tu histórico."
        )
    }

    func testOnlyDaysOlderThanTodayAreLocked() {
        // A free account on day 8 may still open today (day 8 is the last day).
        let today = days(count: 1, daysSinceAnchor: 8)

        let rows = HistoryGating.rows(days: today, access: access(plan: .free, daysSinceAnchor: 8))

        XCTAssertEqual(rows, [.day(today[0])])
    }

    // MARK: - Premium

    func testAPremiumAccountSeesEveryDay() {
        let allDays = days(count: 30, daysSinceAnchor: 30)

        let rows = HistoryGating.rows(
            days: allDays,
            access: access(plan: .premium, daysSinceAnchor: 30)
        )

        XCTAssertEqual(rows, allDays.map(HistoryRow.day))
    }

    // MARK: - Row identity

    /// `HistoryView` renders the rows with `ForEach(rows)`, so every row needs an
    /// id that outlives the recomputation of `HistoryGating.rows`: the day key for
    /// a day row, and one fixed value for the single upsell row.
    func testRowIdentityIsTheDayKeyOrTheFixedLockedValue() {
        let day = days(count: 1, daysSinceAnchor: 3)[0]

        XCTAssertEqual(HistoryRow.day(day).id, "day-3")
        XCTAssertEqual(HistoryRow.day(day).id, day.dayKey)
        // The upsell row is one row whatever it counts, so its id cannot depend
        // on the number of hidden days.
        XCTAssertEqual(HistoryRow.locked(hiddenDayCount: 3).id, "locked")
        XCTAssertEqual(HistoryRow.locked(hiddenDayCount: 12).id, "locked")
    }

    /// Recomputing the rows (every render does) must not change any id, and no two
    /// rows of a list may share one: that is what makes `ForEach` keep its rows.
    func testRowIdentityIsStableAndUniqueAcrossRecomputation() {
        let allDays = days(count: 5, daysSinceAnchor: 10)
        let plan = access(plan: .free, daysSinceAnchor: 10)

        let rows = HistoryGating.rows(days: allDays, access: plan)
        let recomputed = HistoryGating.rows(days: allDays, access: plan)

        XCTAssertEqual(rows.map(\.id), ["day-10", "locked"])
        XCTAssertEqual(rows.map(\.id), recomputed.map(\.id))
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    // MARK: - Empty

    func testNoDaysProduceNoRows() {
        XCTAssertTrue(
            HistoryGating.rows(days: [], access: access(plan: .free, daysSinceAnchor: 10)).isEmpty
        )
    }
}
