import Foundation

/// Day keys of `date` columns (`daily_scores.day`, `league_weekly_ranking`'s
/// `p_week_start`): PostgREST hands them back as `yyyy-MM-dd` text.
///
/// The writing side of the same format already lives in `DriveDay.key(for:)`
/// (S6 upload path); this is only its parser.
enum DayKey {

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: key)
    }
}

/// Week boundaries of the league ranking (S7).
///
/// `public.league_weekly_ranking(p_league_id, p_week_start)` reads the seven days
/// that start at `p_week_start`, and the MVP ranks the week that starts on Monday.
enum WeekBounds {

    /// Monday 00:00 of the week `date` belongs to, in the calendar's time zone.
    static func monday(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        // `weekday` is 1 for Sunday … 7 for Saturday, so this maps Monday to 0 and
        // Sunday to 6.
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    /// `yyyy-MM-dd` of that Monday, the exact shape the RPC expects.
    static func mondayKey(for date: Date, calendar: Calendar = .current) -> String {
        DriveDay.key(for: monday(for: date, calendar: calendar), calendar: calendar)
    }
}
