import Foundation

/// Timestamps of the upload path (S10).
///
/// `drives.started_at` / `ended_at` are `timestamptz`, so they are sent as
/// ISO-8601 in UTC: no reliance on the JSON encoder's date strategy.
enum DriveISO8601 {

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

/// Day grouping for `daily_scores` (S6).
///
/// The day is the Europe/Madrid day, not the device day: the server derives the
/// same drive's day in Madrid (`madrid_today()`, the `xp_ledger` day) and rejects
/// a lesson or quest filed for any other day (B1 of the QA report). The calendar
/// stays injectable so tests can pin it to UTC.
enum DriveDay {

    /// `yyyy-MM-dd`, the format of the `date` column.
    static func key(for date: Date, calendar: Calendar = .madrid) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func start(of date: Date, calendar: Calendar = .madrid) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Exclusive upper bound of the day, used as `started_at < end(of:)`.
    static func end(of date: Date, calendar: Calendar = .madrid) -> Date {
        calendar.date(byAdding: .day, value: 1, to: start(of: date, calendar: calendar)) ?? date
    }
}
