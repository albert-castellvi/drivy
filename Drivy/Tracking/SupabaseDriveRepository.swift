import Foundation
import Supabase

/// S10 upload path: one summarized row in `public.drives`, plus the recomputed
/// daily score in `public.daily_scores`.
///
/// Row Level Security requires `user_id = auth.uid()`, so the user id comes from
/// the current session rather than from the caller.
struct SupabaseDriveRepository: DriveUploading {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func upload(_ record: DriveRecord) async throws {
        let userID = try await client.auth.session.user.id.uuidString

        try await client
            .from("drives")
            .insert(DriveRowPayload(record: record, userID: userID))
            .execute()

        // S6: the daily score is the distance-weighted average of every drive of
        // the day, so it is recomputed from the rows the server now holds. That
        // keeps devices and reinstalls consistent instead of trusting a local
        // counter.
        //
        // Madrid, not the device zone: `xp_ledger` files the same drive under
        // `(started_at at time zone 'Europe/Madrid')::date`, so a device an hour
        // off would count the drive for the streak on one day and for XP on the
        // next (B1 of the QA report).
        let dayCalendar = Calendar.madrid
        let day = DriveDay.key(for: record.startedAt, calendar: dayCalendar)
        let startedAfter = DriveISO8601.string(
            from: DriveDay.start(of: record.startedAt, calendar: dayCalendar)
        )
        let startedBefore = DriveISO8601.string(
            from: DriveDay.end(of: record.startedAt, calendar: dayCalendar)
        )

        let rows: [DriveScoreRow] = try await client
            .from("drives")
            .select("score,distance_km")
            .eq("user_id", value: userID)
            .gte("started_at", value: startedAfter)
            .lt("started_at", value: startedBefore)
            .execute()
            .value

        guard let dailyScore = DailyScoreCalculator.dailyScore(from: rows.map(\.aggregateInput)) else {
            // Only reachable if the row just inserted is not readable back; the
            // drive itself is already stored, so there is nothing to retry here.
            return
        }

        try await client
            .from("daily_scores")
            .upsert(
                DailyScoreRowPayload(dailyScore: dailyScore, userID: userID, day: day),
                onConflict: "user_id,day"
            )
            .execute()
    }
}

/// Minimal projection of `public.drives` for the daily aggregate.
private struct DriveScoreRow: Decodable {

    let score: Int
    let distanceKm: Double

    var aggregateInput: DriveScoreInput {
        DriveScoreInput(score: score, distanceKm: distanceKm)
    }

    enum CodingKeys: String, CodingKey {
        case score
        case distanceKm = "distance_km"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.score = try container.decode(Int.self, forKey: .score)

        // `distance_km` is a Postgres `numeric`, which PostgREST may serialize
        // as a JSON number or as a string: accept both instead of failing the
        // whole daily score on a formatting detail.
        if let value = try? container.decode(Double.self, forKey: .distanceKm) {
            self.distanceKm = value
        } else {
            let value = try container.decode(String.self, forKey: .distanceKm)
            self.distanceKm = Double(value) ?? 0
        }
    }
}
