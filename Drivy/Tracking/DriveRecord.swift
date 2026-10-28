import Foundation

/// Summary of one finished drive: the only drive data that leaves the device
/// (S10, "las muestras crudas de GPS/Motion se suben resumidas"). It maps 1:1 to
/// a `public.drives` row, except for `events`, which stay on the phone (S2, S12).
/// D4: the record carries a client-generated `id` that becomes the `drives.id`
/// primary key of the upload, so a retried upload is idempotent: the server
/// either creates the row or finds it already stored — never a second row.
/// It maps 1:1 to a `public.drives` row, except for `events`, which stay on the
/// phone (S2, S12).
struct DriveRecord: Codable, Equatable {

    /// Primary key the upload sends as `drives.id`, generated once when the
    /// drive stops (D4). Retries of the same drive reuse it, so the insert can
    /// ignore a primary-key conflict instead of duplicating or failing.
    let id: UUID

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

    /// S2: every event the score counted, in time order, with the coordinate of
    /// the fix it happened on when the route of this device was available at the
    /// moment of stopping.
    ///
    /// Local only and deliberately absent from `DriveRowPayload`: no coordinate
    /// is ever uploaded (S10, S12). It lives on the record so the post-drive
    /// summary can draw the events on the route without asking the engine again.
    let events: [DriveEvent]

    /// `events` defaults to the ones the engine already counted on `score`; the
    /// parameter exists for the caller that holds a different set (a re-score) and
    /// so every previous call site keeps working unchanged.
    init(score: DriveScore, startedAt: Date, events: [DriveEvent]? = nil) {
        self.id = UUID()
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
        self.events = events ?? score.events
    }
}

/// Free-form `summary` jsonb of a drive row. Deliberately tiny: enough to know
/// how the score was produced without storing a single raw sample.
struct DriveSummary: Codable, Equatable {

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

// MARK: - Codable (D4)
//
// `DriveEvent` and `DriveCoordinate` live in the Scoring layer and are
// deliberately not `Codable` (and `DriveEventKind` carries no `Codable`
// conformance), so the events are (de)serialized by hand here instead of via
// synthesized conformance: the pending store round-trips the whole record,
// including where each counted event happened (S2).

extension DriveRecord {

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, distanceKm, durationSeconds, score
        case harshBrakes, harshAccelerations, phoneUseEvents, speedingEvents
        case connectedMode, summary, events
    }

    private enum EventKeys: String, CodingKey {
        case kind, timestamp
        case latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        score = try container.decode(Int.self, forKey: .score)
        harshBrakes = try container.decode(Int.self, forKey: .harshBrakes)
        harshAccelerations = try container.decode(Int.self, forKey: .harshAccelerations)
        phoneUseEvents = try container.decode(Int.self, forKey: .phoneUseEvents)
        speedingEvents = try container.decode(Int.self, forKey: .speedingEvents)
        connectedMode = try container.decode(Bool.self, forKey: .connectedMode)
        summary = try container.decode(DriveSummary.self, forKey: .summary)

        var eventsContainer = try container.nestedUnkeyedContainer(forKey: .events)
        var decodedEvents: [DriveEvent] = []
        while !eventsContainer.isAtEnd {
            let eventContainer = try eventsContainer.nestedContainer(keyedBy: EventKeys.self)
            let rawKind = try eventContainer.decode(String.self, forKey: .kind)
            guard let kind = DriveEventKind(rawValue: rawKind) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: eventContainer,
                    debugDescription: "Unknown drive event kind: \(rawKind)"
                )
            }
            let timestamp = try eventContainer.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
            let coordinate: DriveCoordinate?
            if eventContainer.contains(.latitude) {
                coordinate = DriveCoordinate(
                    latitude: try eventContainer.decode(Double.self, forKey: .latitude),
                    longitude: try eventContainer.decode(Double.self, forKey: .longitude)
                )
            } else {
                coordinate = nil
            }
            decodedEvents.append(
                DriveEvent(kind: kind, timestamp: timestamp, coordinate: coordinate)
            )
        }
        events = decodedEvents
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(distanceKm, forKey: .distanceKm)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(score, forKey: .score)
        try container.encode(harshBrakes, forKey: .harshBrakes)
        try container.encode(harshAccelerations, forKey: .harshAccelerations)
        try container.encode(phoneUseEvents, forKey: .phoneUseEvents)
        try container.encode(speedingEvents, forKey: .speedingEvents)
        try container.encode(connectedMode, forKey: .connectedMode)
        try container.encode(summary, forKey: .summary)

        var eventsContainer = container.nestedUnkeyedContainer(forKey: .events)
        for event in events {
            var eventContainer = eventsContainer.nestedContainer(keyedBy: EventKeys.self)
            try eventContainer.encode(event.kind.rawValue, forKey: .kind)
            try eventContainer.encodeIfPresent(event.timestamp, forKey: .timestamp)
            if let coordinate = event.coordinate {
                try eventContainer.encode(coordinate.latitude, forKey: .latitude)
                try eventContainer.encode(coordinate.longitude, forKey: .longitude)
            }
        }
    }
}
