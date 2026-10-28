import Foundation
@testable import Drivy

/// Progress boundary of the Hoy tests (S1, S4, S6, S8) with per-call control.
///
/// `FakeProgressDataLoader` fails every call at once or none; the Hoy screen has to
/// survive a failure of the *extra* reads (XP, quests) while the core ones still
/// answer, so that case needs a stub that can fail one call on its own.
final class StubProgressDataLoader: ProgressDataLoading {

    enum StubError: Error, Equatable {
        case unavailable
    }

    var lessonDayKeys: [String] = []
    var repairs: [StreakRepairRecord] = []
    var storedQuestIDs: [String] = []
    var xpTotals: XPTotals = .zero

    /// Call-level failures.
    var lessonDaysError: Error?
    var xpError: Error?
    var questsError: Error?

    private(set) var lessonDayCalls: [(from: String, to: String)] = []
    private(set) var xpWeekStarts: [String] = []
    private(set) var questDays: [String] = []

    func lessonDays(from firstDay: String, to lastDay: String) async throws -> [String] {
        lessonDayCalls.append((firstDay, lastDay))
        if let lessonDaysError {
            throw lessonDaysError
        }
        return lessonDayKeys.filter { $0 >= firstDay && $0 <= lastDay }
    }

    func recordLesson(day: String, correct: Int, total: Int) async throws {}

    func completedQuests(day: String) async throws -> [String] {
        questDays.append(day)
        if let questsError {
            throw questsError
        }
        return storedQuestIDs
    }

    func recordQuest(day: String, questID: String) async throws {
        storedQuestIDs.append(questID)
    }

    func habitLevels() async throws -> [HabitLevelRecord] { [] }

    func recordHabitLevel(unit: String, level: Int) async throws {}

    func streakRepairs() async throws -> [StreakRepairRecord] { repairs }

    func recordStreakRepair(day: String) async throws {}

    func xp(weekStart: String) async throws -> XPTotals {
        xpWeekStarts.append(weekStart)
        if let xpError {
            throw xpError
        }
        return xpTotals
    }

    func drives(since start: Date) async throws -> [DriveHistoryRow] { [] }
}
