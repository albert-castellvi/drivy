import Foundation

/// The single piece of advice of the post-drive summary (S2: "un consejo según el
/// componente que más penalizó").
///
/// The rule lives here, as a pure value type, so the sheet has no logic of its own
/// and the choice is asserted with the same code the UI runs. The coefficients come
/// from `ScoringRules` through `DriveEventKind.penaltyPerKm`, so the advice ranks
/// the components with the numbers that produced the score.
///
/// No advice ever invites to drive more, further or more often: the loop rewards
/// driving better (S2, S4).
enum DebriefTip: String, Equatable, CaseIterable {

    case harshBrake
    case harshAcceleration
    case speeding
    case phoneUse

    /// Nothing cost points: the summary congratulates instead of correcting.
    case clean

    /// Heaviest component first. It is also the fixed tie-break order, so the same
    /// drive always gets the same advice regardless of the order in which the
    /// events were counted.
    static let preferenceOrder: [DebriefTip] = [.phoneUse, .harshBrake, .speeding, .harshAcceleration]

    /// Event kind this advice talks about; `nil` for `.clean`.
    var kind: DriveEventKind? {
        switch self {
        case .harshBrake:
            return .harshBrake
        case .harshAcceleration:
            return .harshAcceleration
        case .speeding:
            return .speeding
        case .phoneUse:
            return .phoneUse
        case .clean:
            return nil
        }
    }

    // MARK: - Rule

    /// Advice for the component that cost the most points in `record` (S2).
    ///
    /// The cost of a component is its count times its per-event, per-km weight —
    /// the same term `ScoringEngine` charges. A drive where nothing was charged
    /// (no events at all, or phone use in connected mode, which S13 waives) gets
    /// the positive `.clean` message instead of an advice about something free.
    static func tip(for record: DriveRecord) -> DebriefTip {
        var best: DebriefTip = .clean
        var bestPenalty = 0.0

        for candidate in preferenceOrder {
            let penalty = self.penalty(of: candidate, in: record)
            // Strict comparison: on a tie the earlier (heavier) candidate wins.
            if penalty > bestPenalty {
                best = candidate
                bestPenalty = penalty
            }
        }
        return best
    }

    /// Points the component behind `tip` cost in `record`, in the engine's own
    /// units. Zero for `.clean` and for a waived phone-use penalty (S13).
    static func penalty(of tip: DebriefTip, in record: DriveRecord) -> Double {
        guard let kind = tip.kind else { return 0 }
        return penalty(for: kind, in: record)
    }

    /// `count × weightPerKm / effectiveKm`, exactly the term the score charged.
    ///
    /// The effective distance is the same for every kind, so it only matters for
    /// the size of the number, never for which component wins.
    static func penalty(for kind: DriveEventKind, in record: DriveRecord) -> Double {
        if kind == .phoneUse && record.connectedMode {
            return 0
        }
        let effectiveKm = max(record.distanceKm, ScoringRules.minimumDistanceKm)
        return Double(record.eventCount(of: kind)) * kind.penaltyPerKm / effectiveKm
    }

    // MARK: - Copy

    /// Spanish, because it is user-facing copy (the app has no localization).
    var title: String {
        switch self {
        case .harshBrake:
            return "Frenadas bruscas"
        case .harshAcceleration:
            return "Aceleraciones bruscas"
        case .speeding:
            return "Velocidad"
        case .phoneUse:
            return "Uso del móvil"
        case .clean:
            return "Sin incidencias"
        }
    }

    var message: String {
        switch self {
        case .harshBrake:
            return "Frena antes y con más suavidad: cada frenada brusca resta nota."
        case .harshAcceleration:
            return "Acelera de forma progresiva: los arranques bruscos restan nota."
        case .speeding:
            return "Mantén la velocidad dentro del límite: cada exceso resta nota."
        case .phoneUse:
            return "Deja el móvil fuera de alcance: cada uso al volante resta nota."
        case .clean:
            return "Nada que corregir: no has perdido puntos en este trayecto."
        }
    }

    /// SF Symbol of the advice card.
    var systemImage: String {
        switch self {
        case .harshBrake:
            return "hand.raised.fill"
        case .harshAcceleration:
            return "arrow.up.right"
        case .speeding:
            return "speedometer"
        case .phoneUse:
            return "iphone"
        case .clean:
            return "checkmark.seal.fill"
        }
    }
}
