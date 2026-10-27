import Foundation

/// Projection of `public.daily_scores` (S6, S10). The column names are the
/// migration's, because PostgREST matches them verbatim.
struct DailyScoreRecord: Decodable, Equatable {

    /// `yyyy-MM-dd`, the user's local day.
    let day: String

    let score: Int

    let distanceKm: Double

    let drivesCount: Int

    enum CodingKeys: String, CodingKey {
        case day
        case score
        case distanceKm = "distance_km"
        case drivesCount = "drives_count"
    }

    init(day: String, score: Int, distanceKm: Double, drivesCount: Int) {
        self.day = day
        self.score = score
        self.distanceKm = distanceKm
        self.drivesCount = drivesCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        day = try container.decode(String.self, forKey: .day)
        score = try container.decode(Int.self, forKey: .score)
        // `numeric(8, 2)`: a JSON number or a string, depending on the serializer.
        distanceKm = try container.decodeDecimal(forKey: .distanceKm)
        drivesCount = try container.decode(Int.self, forKey: .drivesCount)
    }
}

/// Row of `public.drives` shown in today's list and in the drive detail (T4).
///
/// Only the summarized numbers the server keeps: the raw GPS/motion samples never
/// leave the device (S10), so there is no coordinate here and the detail screen
/// has to rely on a local track for the map.
struct DriveHistoryRow: Decodable, Equatable, Identifiable {

    let id: String

    let startedAt: Date

    let endedAt: Date

    let distanceKm: Double

    let durationSeconds: Int

    let score: Int

    let harshBrakes: Int

    let harshAccelerations: Int

    let phoneUseEvents: Int

    let speedingEvents: Int

    let connectedMode: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceKm = "distance_km"
        case durationSeconds = "duration_s"
        case score
        case harshBrakes = "harsh_brakes"
        case harshAccelerations = "harsh_accelerations"
        case phoneUseEvents = "phone_use_events"
        case speedingEvents = "speeding_events"
        case connectedMode = "connected_mode"
    }

    init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        distanceKm: Double,
        durationSeconds: Int,
        score: Int,
        harshBrakes: Int,
        harshAccelerations: Int,
        phoneUseEvents: Int,
        speedingEvents: Int,
        connectedMode: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.score = score
        self.harshBrakes = harshBrakes
        self.harshAccelerations = harshAccelerations
        self.phoneUseEvents = phoneUseEvents
        self.speedingEvents = speedingEvents
        self.connectedMode = connectedMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decodeTimestamp(forKey: .startedAt)
        endedAt = try container.decodeTimestamp(forKey: .endedAt)
        distanceKm = try container.decodeDecimal(forKey: .distanceKm)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        score = try container.decode(Int.self, forKey: .score)
        harshBrakes = try container.decode(Int.self, forKey: .harshBrakes)
        harshAccelerations = try container.decode(Int.self, forKey: .harshAccelerations)
        phoneUseEvents = try container.decode(Int.self, forKey: .phoneUseEvents)
        speedingEvents = try container.decode(Int.self, forKey: .speedingEvents)
        connectedMode = try container.decode(Bool.self, forKey: .connectedMode)
    }

    /// Reduced form used by the daily average (S6): the same input the upload path
    /// feeds to `DailyScoreCalculator`.
    var aggregateInput: DriveScoreInput {
        DriveScoreInput(score: score, distanceKm: distanceKm)
    }

    /// Average speed of the drive, derived from the stored numbers.
    var averageSpeedKmh: Double {
        guard durationSeconds > 0 else { return 0 }
        return distanceKm / (Double(durationSeconds) / 3600)
    }
}
