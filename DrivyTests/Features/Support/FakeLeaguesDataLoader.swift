import Foundation
@testable import Drivy

/// Test double for the Supabase boundary of the Leagues tab (S7): no network.
final class FakeLeaguesDataLoader: LeaguesDataLoading {

    enum FakeError: Error, Equatable {
        case notConfigured
        case network
    }

    var leaguesResult: Result<[LeagueRecord], Error> = .success([])
    var createOutcome: Result<LeagueRecord, Error> = .failure(FakeError.notConfigured)
    var joinOutcome: Result<String, Error> = .failure(FakeError.notConfigured)
    var rankingOutcome: Result<[LeagueRankingRow], Error> = .success([])

    private(set) var leaguesCallCount = 0
    private(set) var createCalls: [(name: String, inviteCode: String, userID: String)] = []
    private(set) var joinCalls: [String] = []
    private(set) var rankingCalls: [(leagueID: String, weekStart: String)] = []

    func leagues(userID: String) async throws -> [LeagueRecord] {
        leaguesCallCount += 1
        return try leaguesResult.get()
    }

    func createLeague(name: String, inviteCode: String, userID: String) async throws -> LeagueRecord {
        createCalls.append((name, inviteCode, userID))
        return try createOutcome.get()
    }

    func joinLeague(inviteCode: String) async throws -> String {
        joinCalls.append(inviteCode)
        return try joinOutcome.get()
    }

    func weeklyRanking(leagueID: String, weekStart: String) async throws -> [LeagueRankingRow] {
        rankingCalls.append((leagueID, weekStart))
        return try rankingOutcome.get()
    }
}
