import Foundation

extension Calendar {

    /// The one calendar of every day and week key that is stored in, or compared
    /// with, Supabase.
    ///
    /// The server pins the zone: `madrid_today()`, `madrid_week_start()`, the
    /// `xp_ledger` day `(started_at at time zone 'Europe/Madrid')::date` and the
    /// `check (day between madrid_today() - 1 and madrid_today())` of
    /// `supabase/migrations/20261028084225_0002_duolingo_loop.sql` all use Europe/Madrid. With
    /// the device zone instead, a Canarias phone (one hour behind) writes the
    /// next day's key between 23:00 and 00:00: the CHECK rejects the lesson and
    /// the quest silently loses its XP (B1 of the QA report).
    ///
    /// So this is the default for anything that travels to the server. Display
    /// formatting keeps `Calendar.current`: that one must follow the device.
    static let madrid: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}

/// Day keys of `date` columns (`daily_scores.day`, `league_weekly_ranking`'s
/// `p_week_start`): PostgREST hands them back as `yyyy-MM-dd` text.
///
/// The writing side of the same format already lives in `DriveDay.key(for:)`
/// (S6 upload path); this is only its parser. Both sides default to
/// `Calendar.madrid`, the zone the server reads the same keys with.
enum DayKey {

    static func date(from key: String, calendar: Calendar = .madrid) -> Date? {
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
/// The boundary is Madrid by default (`Calendar.madrid`), like
/// `madrid_week_start()` on the server: sending the device Monday would ask for a
/// week the server has not formed yet.
enum WeekBounds {

    /// Monday 00:00 of the week `date` belongs to, in the calendar's time zone.
    static func monday(for date: Date, calendar: Calendar = .madrid) -> Date {
        let day = calendar.startOfDay(for: date)
        // `weekday` is 1 for Sunday … 7 for Saturday, so this maps Monday to 0 and
        // Sunday to 6.
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    /// `yyyy-MM-dd` of that Monday, the exact shape the RPC expects.
    static func mondayKey(for date: Date, calendar: Calendar = .madrid) -> String {
        DriveDay.key(for: monday(for: date, calendar: calendar), calendar: calendar)
    }
}
