import Foundation

/// Formatting shared by the core screens (T4).
///
/// Deliberately explicit instead of locale-driven: the strings stay the same
/// everywhere (matching the T3 drive card) and can be asserted in tests.
enum DriveFormat {

    /// `nil` means "nothing to show yet", never a fake zero.
    static func score(_ score: Int?) -> String {
        score.map(String.init) ?? "—"
    }

    static func distance(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    static func speed(_ kmh: Double) -> String {
        String(format: "%.0f km/h", kmh)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60

        let twoDigits: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(remaining))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(remaining))"
    }

    /// Local time of the day, e.g. `18:42`.
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Day and month, e.g. `13 nov` (used by the weekly ranking header).
    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func drivesCount(_ count: Int) -> String {
        count == 1 ? "1 trayecto" : "\(count) trayectos"
    }
}
