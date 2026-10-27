import Foundation
import Supabase

/// Boundary between the Hoy screen and the Supabase reads it needs (S6), so the
/// view models are tested without a network.
protocol TodayDataLoading {

    /// `public.daily_scores` rows of the inclusive day-key window, newest first.
    func dailyScores(
        userID: String,
        from firstDay: String,
        to lastDay: String
    ) async throws -> [DailyScoreRecord]

    /// `public.drives` rows of one local day, newest first.
    func drives(userID: String, dayStart: Date, dayEnd: Date) async throws -> [DriveHistoryRow]
}

/// S10 read path of the Hoy tab.
///
/// Row Level Security already limits every table to `user_id = auth.uid()`, so
/// nothing here can read another user's data; the filter is sent anyway because it
/// keeps the `(user_id, started_at)` index in use.
struct SupabaseTodayRepository: TodayDataLoading {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func dailyScores(
        userID: String,
        from firstDay: String,
        to lastDay: String
    ) async throws -> [DailyScoreRecord] {
        let rows: [DailyScoreRecord] = try await client
            .from("daily_scores")
            .select("day,score,distance_km,drives_count")
            .eq("user_id", value: userID)
            .gte("day", value: firstDay)
            .lte("day", value: lastDay)
            .order("day", ascending: false)
            .execute()
            .value

        return rows
    }

    func drives(userID: String, dayStart: Date, dayEnd: Date) async throws -> [DriveHistoryRow] {
        // Only the summarized columns: the raw samples are not on the server (S10).
        let rows: [DriveHistoryRow] = try await client
            .from("drives")
            .select(
                "id,started_at,ended_at,distance_km,duration_s,score,"
                    + "harsh_brakes,harsh_accelerations,phone_use_events,"
                    + "speeding_events,connected_mode"
            )
            .eq("user_id", value: userID)
            .gte("started_at", value: DriveISO8601.string(from: dayStart))
            .lt("started_at", value: DriveISO8601.string(from: dayEnd))
            .order("started_at", ascending: false)
            .execute()
            .value

        return rows
    }
}
