import Foundation

/// Streak state of the current run (S6).
struct Streak: Equatable {

    /// Days with at least one drive inside the current run. A grace day keeps the
    /// run alive but does not add to the count, like a Duolingo freeze.
    let days: Int

    /// True when a one-day gap is already part of the run.
    let usesGraceDay: Bool

    /// True when today already has a drive.
    let isTodayRecorded: Bool

    static let empty = Streak(days: 0, usesGraceDay: false, isTodayRecorded: false)
}

/// Streak rule (S6, verbatim): "Racha = días consecutivos con ≥ 1 trayecto. La
/// racha se rompe con 2 días sin conducir (gracia de 1 día, estilo Duolingo con
/// 'hielo')".
///
/// The run is therefore read backwards from today: a single missing day keeps it
/// alive (that missed day *is* the grace day, "hielo") and two consecutive missing
/// days end it. A day without a drive that happens to be *today* is not a gap at
/// all: the user still has the rest of the day to drive, so the streak is shown as
/// it stands.
enum StreakCalculator {

    static func streak(
        drivingDays: Set<Date>,
        today: Date,
        calendar: Calendar = .current
    ) -> Streak {
        let days = Set(drivingDays.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)
        let isTodayRecorded = days.contains(todayStart)

        guard let earliest = days.min() else {
            return .empty
        }

        var cursor = isTodayRecorded
            ? todayStart
            : (calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart)
        var count = 0
        var usesGraceDay = false
        var missingRun = 0

        while cursor >= earliest {
            if days.contains(cursor) {
                count += 1
                missingRun = 0
            } else {
                missingRun += 1
                // S6: two days without driving is what breaks the streak. The run
                // that starts after the break has its grace day available again.
                if missingRun >= 2 {
                    usesGraceDay = false
                    break
                }
                usesGraceDay = true
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        guard count > 0 else {
            return Streak(days: 0, usesGraceDay: false, isTodayRecorded: isTodayRecorded)
        }
        return Streak(days: count, usesGraceDay: usesGraceDay, isTodayRecorded: isTodayRecorded)
    }
}

// MARK: - Copy of the racha card

extension Streak {

    /// Headline of the card. Spanish, because it is user-facing copy.
    var headline: String {
        switch days {
        case 0:
            return "Sin racha"
        case 1:
            return "1 día de racha"
        default:
            return "\(days) días de racha"
        }
    }

    /// Second line: what keeps the run alive and whether the grace day is spent.
    var detail: String {
        guard days > 0 else {
            return "Registra tu primer trayecto para empezar la racha."
        }
        if usesGraceDay {
            return "Has usado tu día de gracia: dos días sin conducir y la racha se rompe."
        }
        if isTodayRecorded {
            return "Hoy ya cuenta. Un día sin conducir no la rompe."
        }
        return "Conduce hoy para mantenerla. Un día sin conducir no la rompe."
    }
}
