import Foundation
import Supabase

/// Lifetime and current-week XP of the signed-in user (S4), from `public.my_xp`.
struct XPTotals: Decodable, Equatable {

    let totalXP: Int

    let weekXP: Int

    static let zero = XPTotals(totalXP: 0, weekXP: 0)

    init(totalXP: Int, weekXP: Int) {
        self.totalXP = totalXP
        self.weekXP = weekXP
    }

    enum CodingKeys: String, CodingKey {
        case totalXP = "total_xp"
        case weekXP = "week_xp"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalXP = try container.decodeInteger(forKey: .totalXP)
        weekXP = try container.decodeInteger(forKey: .weekXP)
    }
}

/// One level of the habit path already passed (S3), from `public.habit_levels`.
struct HabitLevelRecord: Decodable, Equatable {

    /// Stable unit key: `smooth_braking`, `smooth_acceleration`, `no_phone`,
    /// `speed` or `connected` (the values the table accepts).
    let unit: String

    let level: Int

    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case unit
        case level
        case completedAt = "completed_at"
    }
}

/// A day of a broken streak forgiven with the premium repair (S8).
struct StreakRepairRecord: Decodable, Equatable {

    /// `yyyy-MM-dd` key of the forgiven day.
    let day: String

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case day
        case createdAt = "created_at"
    }
}

/// Boundary between the Duolingo loop (streak, lessons, quests, habit path, XP)
/// and Supabase, so every feature of `odd/tasks/duolingo-loop.md` reads and
/// writes progress through one place and is tested without a network.
///
/// Day arguments are `yyyy-MM-dd` keys of the local calendar (`DriveDay.key`).
/// Writes are idempotent: recording the same lesson, quest, level or repair twice
/// is a no-op, so a retry or a double tap never fails.
protocol ProgressDataLoading {

    /// Days with a completed theory lesson in the inclusive window.
    func lessonDays(from firstDay: String, to lastDay: String) async throws -> [String]

    func recordLesson(day: String, correct: Int, total: Int) async throws

    /// Quest ids already completed on `day`.
    func completedQuests(day: String) async throws -> [String]

    func recordQuest(day: String, questID: String) async throws

    func habitLevels() async throws -> [HabitLevelRecord]

    func recordHabitLevel(unit: String, level: Int) async throws

    func streakRepairs() async throws -> [StreakRepairRecord]

    func recordStreakRepair(day: String) async throws

    /// XP totals; `weekStart` is the Monday key of the current week.
    func xp(weekStart: String) async throws -> XPTotals

    /// Drives that started at or after `start`, oldest first (habit path, quests).
    func drives(since start: Date) async throws -> [DriveHistoryRow]
}

/// Supabase implementation. RLS limits every table to `user_id = auth.uid()`
/// and the inserts rely on the `default auth.uid()` of each `user_id` column,
/// so no user id is ever sent.
struct SupabaseProgressRepository: ProgressDataLoading {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    private struct DayRow: Decodable {
        let day: String
    }

    private struct QuestRow: Decodable {
        let questID: String

        enum CodingKeys: String, CodingKey {
            case questID = "quest_id"
        }
    }

    private struct LessonInsert: Encodable {
        let day: String
        let correct: Int
        let total: Int
    }

    private struct QuestInsert: Encodable {
        let day: String
        let questID: String

        enum CodingKeys: String, CodingKey {
            case day
            case questID = "quest_id"
        }
    }

    private struct HabitLevelInsert: Encodable {
        let unit: String
        let level: Int
    }

    private struct RepairInsert: Encodable {
        let day: String
    }

    func lessonDays(from firstDay: String, to lastDay: String) async throws -> [String] {
        let rows: [DayRow] = try await client
            .from("lesson_completions")
            .select("day")
            .gte("day", value: firstDay)
            .lte("day", value: lastDay)
            .execute()
            .value

        return rows.map(\.day)
    }

    func recordLesson(day: String, correct: Int, total: Int) async throws {
        try await client
            .from("lesson_completions")
            .upsert(LessonInsert(day: day, correct: correct, total: total), ignoreDuplicates: true)
            .execute()
    }

    func completedQuests(day: String) async throws -> [String] {
        let rows: [QuestRow] = try await client
            .from("quest_completions")
            .select("quest_id")
            .eq("day", value: day)
            .execute()
            .value

        return rows.map(\.questID)
    }

    func recordQuest(day: String, questID: String) async throws {
        try await client
            .from("quest_completions")
            .upsert(QuestInsert(day: day, questID: questID), ignoreDuplicates: true)
            .execute()
    }

    func habitLevels() async throws -> [HabitLevelRecord] {
        let rows: [HabitLevelRecord] = try await client
            .from("habit_levels")
            .select("unit,level,completed_at")
            .order("completed_at", ascending: true)
            .execute()
            .value

        return rows
    }

    func recordHabitLevel(unit: String, level: Int) async throws {
        try await client
            .from("habit_levels")
            .upsert(HabitLevelInsert(unit: unit, level: level), ignoreDuplicates: true)
            .execute()
    }

    func streakRepairs() async throws -> [StreakRepairRecord] {
        let rows: [StreakRepairRecord] = try await client
            .from("streak_repairs")
            .select("day,created_at")
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows
    }

    func recordStreakRepair(day: String) async throws {
        try await client
            .from("streak_repairs")
            .upsert(RepairInsert(day: day), ignoreDuplicates: true)
            .execute()
    }

    func xp(weekStart: String) async throws -> XPTotals {
        let rows: [XPTotals] = try await client
            .rpc("my_xp", params: ["p_week_start": weekStart])
            .execute()
            .value

        return rows.first ?? .zero
    }

    func drives(since start: Date) async throws -> [DriveHistoryRow] {
        let rows: [DriveHistoryRow] = try await client
            .from("drives")
            .select(
                "id,started_at,ended_at,distance_km,duration_s,score,"
                    + "harsh_brakes,harsh_accelerations,phone_use_events,"
                    + "speeding_events,connected_mode"
            )
            .gte("started_at", value: DriveISO8601.string(from: start))
            .order("started_at", ascending: true)
            .execute()
            .value

        return rows
    }
}
