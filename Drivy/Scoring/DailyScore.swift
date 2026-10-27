import Foundation

/// Daily Driver Score (S6): distance-weighted average of the day's drives.
struct DailyScore: Equatable {

    let score: Int

    let distanceKm: Double

    let drivesCount: Int
}

/// Pure counterpart of the SQL weekly-ranking average: the client computes the
/// daily score before uploading it to `public.daily_scores` (S6, S10).
enum DailyScoreCalculator {

    /// S6: "Driver Score diario = media ponderada por distancia de los trayectos
    /// del día".
    ///
    /// Drives with no distance carry no weight, so a day whose drives were all
    /// zero-distance falls back to the plain average instead of dividing by 0.
    /// Returns `nil` for an empty day: there is no score to show.
    static func dailyScore(from drives: [DriveScoreInput]) -> DailyScore? {
        guard !drives.isEmpty else { return nil }

        let distances = drives.map { max(0, $0.distanceKm) }
        let totalKm = distances.reduce(0, +)

        let weighted: Double
        if totalKm > 0 {
            let weightedSum = zip(drives, distances).reduce(0.0) { partial, pair in
                partial + Double(pair.0.score) * pair.1
            }
            weighted = weightedSum / totalKm
        } else {
            weighted = Double(drives.reduce(0) { $0 + $1.score }) / Double(drives.count)
        }

        return DailyScore(
            score: min(max(Int(weighted.rounded()), 0), 100),
            distanceKm: (totalKm * 100).rounded() / 100,
            drivesCount: drives.count
        )
    }
}
