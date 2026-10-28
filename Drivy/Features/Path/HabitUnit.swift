import Foundation

/// One unit of the habit path (S3).
///
/// The five units are quality rules the scoring engine already measures, in the
/// order the path plays them: no new metric is invented, and no unit can ask the
/// user to drive more, because a unit only counts drives that already happened.
///
/// `rawValue` is the stable snake_case key shared with `public.habit_levels.unit`
/// (`0002_duolingo_loop.sql` accepts exactly these five), so renaming a case would
/// orphan every level already recorded for it.
enum HabitUnit: String, CaseIterable, Identifiable {

    case smoothBraking = "smooth_braking"
    case smoothAcceleration = "smooth_acceleration"
    case noPhone = "no_phone"
    case speed = "speed"
    case connected = "connected"

    var id: String { rawValue }

    /// Title of the unit on the path. Spanish, because it is user-facing copy.
    var title: String {
        switch self {
        case .smoothBraking:
            return "Frenada suave"
        case .smoothAcceleration:
            return "Arranque suave"
        case .noPhone:
            return "Cero móvil"
        case .speed:
            return "Velocidad"
        case .connected:
            return "Conducción conectada"
        }
    }

    /// The one short tip of the unit (S3): what the driver can do, never how much
    /// to drive.
    var tip: String {
        switch self {
        case .smoothBraking:
            return "Frena con antelación y de forma progresiva."
        case .smoothAcceleration:
            return "Acelera poco a poco, sin tirones."
        case .noPhone:
            return "Deja el móvil fuera de las manos durante el trayecto."
        case .speed:
            return "Mantén la velocidad dentro de los límites."
        case .connected:
            return "Conecta el móvil al coche antes de arrancar."
        }
    }

    /// Node symbol of the trail. Plain glyphs, because the circle behind them is
    /// drawn by the row.
    var symbolName: String {
        switch self {
        case .smoothBraking:
            return "hand.raised.fill"
        case .smoothAcceleration:
            return "arrow.up.forward"
        case .noPhone:
            return "iphone.slash"
        case .speed:
            return "speedometer"
        case .connected:
            return "iphone.radiowaves.left.and.right"
        }
    }

    /// S3: whether one drive satisfies the rule of the unit. The distance floor is
    /// applied by `HabitPathEngine`, not here, so the rule and the floor stay
    /// separately testable.
    func isQualified(_ drive: DriveHistoryRow) -> Bool {
        switch self {
        case .smoothBraking:
            return drive.harshBrakes == 0
        case .smoothAcceleration:
            return drive.harshAccelerations == 0
        case .noPhone:
            return drive.phoneUseEvents == 0
        case .speed:
            return drive.speedingEvents == 0
        case .connected:
            return drive.connectedMode
        }
    }

    /// Unit that has to record its third level before this one opens (S3). `nil`
    /// for the first unit, which is open from the start.
    var previous: HabitUnit? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }
}
