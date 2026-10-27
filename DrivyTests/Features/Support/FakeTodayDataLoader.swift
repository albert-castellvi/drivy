import Foundation
@testable import Drivy

/// Test double for the Supabase read boundary of the Today tab: no network.
final class FakeTodayDataLoader: TodayDataLoading {

    enum FakeError: Error, Equatable {
        case network
    }

    var dailyScoresResult: Result<[DailyScoreRecord], Error> = .success([])
    var drivesResult: Result<[DriveHistoryRow], Error> = .success([])

    private(set) var dailyScoresCalls: [(userID: String, from: String, to: String)] = []
    private(set) var drivesCalls: [(userID: String, dayStart: Date, dayEnd: Date)] = []

    func dailyScores(
        userID: String,
        from firstDay: String,
        to lastDay: String
    ) async throws -> [DailyScoreRecord] {
        dailyScoresCalls.append((userID, firstDay, lastDay))
        return try dailyScoresResult.get()
    }

    func drives(userID: String, dayStart: Date, dayEnd: Date) async throws -> [DriveHistoryRow] {
        drivesCalls.append((userID, dayStart, dayEnd))
        return try drivesResult.get()
    }
}
