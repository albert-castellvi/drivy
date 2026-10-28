import Foundation
@testable import Drivy

/// Test double for `ProgressDataLoading`: an in-memory store with the same
/// idempotent writes as the Supabase tables, and call logs for assertions.
final class FakeProgressDataLoader: ProgressDataLoading {

    enum FakeError: Error, Equatable {
        case network
    }

    /// When set, every call throws it.
    var failure: Error?

    var lessons: [String: (correct: Int, total: Int)] = [:]
    var quests: [String: Set<String>] = [:]
    var levels: [HabitLevelRecord] = []
    var repairs: [StreakRepairRecord] = []
    var xpTotals: XPTotals = .zero
    var driveRows: [DriveHistoryRow] = []

    private(set) var xpWeekStarts: [String] = []
    private(set) var drivesSinceCalls: [Date] = []

    /// Clock of the `completedAt` / `createdAt` the fake stamps on new rows.
    var now: () -> Date = Date.init

    func lessonDays(from firstDay: String, to lastDay: String) async throws -> [String] {
        try check()
        return lessons.keys.filter { $0 >= firstDay && $0 <= lastDay }.sorted()
    }

    func recordLesson(day: String, correct: Int, total: Int) async throws {
        try check()
        if lessons[day] == nil {
            lessons[day] = (correct, total)
        }
    }

    func completedQuests(day: String) async throws -> [String] {
        try check()
        return (quests[day] ?? []).sorted()
    }

    func recordQuest(day: String, questID: String) async throws {
        try check()
        quests[day, default: []].insert(questID)
    }

    func habitLevels() async throws -> [HabitLevelRecord] {
        try check()
        return levels
    }

    func recordHabitLevel(unit: String, level: Int) async throws {
        try check()
        guard !levels.contains(where: { $0.unit == unit && $0.level == level }) else { return }
        levels.append(HabitLevelRecord(unit: unit, level: level, completedAt: now()))
    }

    func streakRepairs() async throws -> [StreakRepairRecord] {
        try check()
        return repairs
    }

    func recordStreakRepair(day: String) async throws {
        try check()
        guard !repairs.contains(where: { $0.day == day }) else { return }
        repairs.append(StreakRepairRecord(day: day, createdAt: now()))
    }

    func xp(weekStart: String) async throws -> XPTotals {
        try check()
        xpWeekStarts.append(weekStart)
        return xpTotals
    }

    func drives(since start: Date) async throws -> [DriveHistoryRow] {
        try check()
        drivesSinceCalls.append(start)
        return driveRows.filter { $0.startedAt >= start }.sorted { $0.startedAt < $1.startedAt }
    }

    private func check() throws {
        if let failure {
            throw failure
        }
    }
}
