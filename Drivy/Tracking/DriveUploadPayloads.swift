import Foundation

/// Row written to `public.drives`. Keys mirror the migration
/// (`supabase/migrations/20261027125528_drivy_schema_v1.sql`) verbatim, because PostgREST
/// matches column names exactly.
///
/// There is no field here for a GPS fix or a motion sample: raw data stays on the
/// device (S10).
struct DriveRowPayload: Encodable, Equatable {

    /// Client-generated primary key (D4): a retried upload reuses it, so the
    /// insert can ignore the duplicate instead of creating a second row.
    let id: UUID
    let userID: String
    let startedAt: String
    let endedAt: String
    let distanceKm: Double
    let durationS: Int
    let score: Int
    let harshBrakes: Int
    let harshAccelerations: Int
    let phoneUseEvents: Int
    let speedingEvents: Int
    let connectedMode: Bool
    let summary: DriveSummaryPayload

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceKm = "distance_km"
        case durationS = "duration_s"
        case score
        case harshBrakes = "harsh_brakes"
        case harshAccelerations = "harsh_accelerations"
        case phoneUseEvents = "phone_use_events"
        case speedingEvents = "speeding_events"
        case connectedMode = "connected_mode"
        case summary
    }

    init(record: DriveRecord, userID: String) {
        self.id = record.id
        self.userID = userID
        self.startedAt = DriveISO8601.string(from: record.startedAt)
        self.endedAt = DriveISO8601.string(from: record.endedAt)
        self.distanceKm = (record.distanceKm * 100).rounded() / 100
        self.durationS = max(1, record.durationSeconds)
        self.score = min(max(record.score, 0), 100)
        self.harshBrakes = record.harshBrakes
        self.harshAccelerations = record.harshAccelerations
        self.phoneUseEvents = record.phoneUseEvents
        self.speedingEvents = record.speedingEvents
        self.connectedMode = record.connectedMode
        self.summary = DriveSummaryPayload(summary: record.summary)
    }
}

/// Row upserted into `public.daily_scores`, keyed by `(user_id, day)` (S6).
struct DailyScoreRowPayload: Encodable, Equatable {

    let userID: String
    let day: String
    let score: Int
    let distanceKm: Double
    let drivesCount: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case day
        case score
        case distanceKm = "distance_km"
        case drivesCount = "drives_count"
    }

    init(dailyScore: DailyScore, userID: String, day: String) {
        self.userID = userID
        self.day = day
        self.score = min(max(dailyScore.score, 0), 100)
        self.distanceKm = (dailyScore.distanceKm * 100).rounded() / 100
        self.drivesCount = max(0, dailyScore.drivesCount)
    }
}

/// `jsonb` companion of a drive row.
struct DriveSummaryPayload: Encodable, Equatable {

    let engineVersion: Int
    let phonePenaltyWaived: Bool
    let averageSpeedKmh: Double

    enum CodingKeys: String, CodingKey {
        case engineVersion = "engine_version"
        case phonePenaltyWaived = "phone_penalty_waived"
        case averageSpeedKmh = "average_speed_kmh"
    }

    init(summary: DriveSummary) {
        self.engineVersion = summary.engineVersion
        self.phonePenaltyWaived = summary.phonePenaltyWaived
        self.averageSpeedKmh = (summary.averageSpeedKmh * 10).rounded() / 10
    }
}
