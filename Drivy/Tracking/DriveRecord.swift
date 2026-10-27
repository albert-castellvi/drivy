import Foundation

/// Summary of one finished drive: the only drive data that leaves the device
/// (S10, "las muestras crudas de GPS/Motion se suben resumidas"). It maps 1:1 to
/// a `public.drives` row.
struct DriveRecord: Equatable {

    let startedAt: Date

    let endedAt: Date

    /// Rounded to 2 decimals, matching `numeric(8, 2)` in the schema.
    let distanceKm: Double

    /// Whole seconds, always at least 1 so the row satisfies `duration_s > 0`.
    let durationSeconds: Int

    let score: Int

    let harshBrakes: Int

    let harshAccelerations: Int

    let phoneUseEvents: Int

    let speedingEvents: Int

    let connectedMode: Bool

    let summary: DriveSummary

    init(score: DriveScore, startedAt: Date) {
        let duration = max(1, Int(score.durationSeconds.rounded()))

        self.startedAt = startedAt
        // `drives` requires `ended_at > started_at`, hence the 1 s floor.
        self.endedAt = startedAt.addingTimeInterval(TimeInterval(duration))
        self.distanceKm = (score.distanceKm * 100).rounded() / 100
        self.durationSeconds = duration
        self.score = score.score
        self.harshBrakes = score.harshBrakes
        self.harshAccelerations = score.harshAccelerations
        self.phoneUseEvents = score.phoneUseEvents
        self.speedingEvents = score.speedingEvents
        self.connectedMode = score.connectedMode
        self.summary = DriveSummary(score: score)
    }
}

/// Free-form `summary` jsonb of a drive row. Deliberately tiny: enough to know
/// how the score was produced without storing a single raw sample.
struct DriveSummary: Equatable {

    let engineVersion: Int

    /// S13: connected mode waives the phone-use penalty, so the row records
    /// whether the count was charged or not.
    let phonePenaltyWaived: Bool

    let averageSpeedKmh: Double

    init(score: DriveScore) {
        let hours = score.durationSeconds / 3600
        let averageSpeed = hours > 0 ? score.distanceKm / hours : 0

        self.engineVersion = ScoringRules.version
        self.phonePenaltyWaived = score.isPhoneUsePenaltyWaived
        self.averageSpeedKmh = (averageSpeed * 10).rounded() / 10
    }
}
