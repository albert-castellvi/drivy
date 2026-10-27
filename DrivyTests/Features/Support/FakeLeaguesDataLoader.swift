import Foundation
@testable import Drivy

/// Test double for the Supabase boundary of the Leagues tab (S5): no network.
final class FakeLeaguesDataLoader: LeaguesDataLoading {

    enum FakeError: Error, Equatable {
        case notConfigured
        case network
    }

    var leaguesResult: Result<[LeagueRecord], Error> = .success([])
    var createOutcome: Result<LeagueRecord, Error> = .failure(FakeError.notConfigured)
    var joinOutcome: Result<String, Error> = .failure(FakeError.notConfigured)
    var rankingOutcome: Result<[LeagueRankingRow], Error> = .success([])

    // MARK: - Public leagues (S5)

    /// Answer of `publicLeagueStatus()`; `nil` means the user never decided.
    var publicLeagueStatusResult: Result<PublicLeagueStatus?, Error> = .success(nil)

    var currentPublicLeagueOutcome: Result<PublicLeagueCurrent, Error> =
        .failure(FakeError.notConfigured)

    var publicLeagueRankingOutcome: Result<[PublicLeagueRankingRow], Error> = .success([])

    /// When set, `setPublicLeagueOptIn` throws it.
    var setOptInError: Error?

    private(set) var leaguesCallCount = 0
    private(set) var createCalls: [(name: String, inviteCode: String, userID: String)] = []
    private(set) var joinCalls: [String] = []
    private(set) var rankingCalls: [(leagueID: String, weekStart: String)] = []
    private(set) var publicLeagueStatusCallCount = 0
    private(set) var currentPublicLeagueCallCount = 0
    private(set) var publicLeagueRankingCallCount = 0
    private(set) var optInCalls: [Bool] = []

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

    func setPublicLeagueOptIn(_ on: Bool) async throws {
        optInCalls.append(on)
        if let setOptInError {
            throw setOptInError
        }
    }

    func publicLeagueStatus() async throws -> PublicLeagueStatus? {
        publicLeagueStatusCallCount += 1
        return try publicLeagueStatusResult.get()
    }

    func currentPublicLeague() async throws -> PublicLeagueCurrent {
        currentPublicLeagueCallCount += 1
        return try currentPublicLeagueOutcome.get()
    }

    func publicLeagueRanking() async throws -> [PublicLeagueRankingRow] {
        publicLeagueRankingCallCount += 1
        return try publicLeagueRankingOutcome.get()
    }
}
