import Foundation

/// Week of the public leagues (S5): the groups are formed on Monday 00:00
/// Europe/Madrid, which is the same `week_start` the SQL side computes with
/// `madrid_week_start()`.
///
/// One fixed zone for every user, like the migration: sending the device zone
/// would make the client ask for a week the server has not formed yet.
enum PublicLeagueWeek {

    static let timeZoneIdentifier = "Europe/Madrid"

    /// Madrid calendar used by the client so its Monday matches the server's.
    ///
    /// It is the shared `Calendar.madrid`, exposed under the name the league
    /// code reads like the migration it mirrors: one definition, not two.
    static var madridCalendar: Calendar { Calendar.madrid }

    /// `yyyy-MM-dd` of the Madrid Monday of `now`, the `p_week_start` shape.
    static func weekStartKey(for now: Date, calendar: Calendar = madridCalendar) -> String {
        WeekBounds.mondayKey(for: now, calendar: calendar)
    }

    /// Whole days until the next Monday 00:00 Madrid: 7 on a Monday, 1 on a
    /// Sunday.
    ///
    /// Counted in calendar days instead of seconds so the DST change cannot
    /// shift the answer by one. Never negative, so a stale clock cannot print a
    /// countdown that already ended.
    static func daysLeft(now: Date, calendar: Calendar = madridCalendar) -> Int {
        let monday = WeekBounds.monday(for: now, calendar: calendar)
        guard let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) else {
            return 0
        }

        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: nextMonday).day ?? 0
        return max(0, days)
    }

    /// Countdown copy of the public section.
    static func daysLeftText(_ days: Int) -> String {
        days == 1 ? "Queda 1 día de liga" : "Quedan \(days) días de liga"
    }
}
