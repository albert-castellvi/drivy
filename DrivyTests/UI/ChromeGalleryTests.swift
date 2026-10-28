import SwiftUI
import UIKit
import XCTest
@testable import Drivy

// MARK: - Galleries of the chrome screens (S8)

/// S8 for the screens W4 owns: the two leagues lists, the public standings with
/// its movement lanes, the paywall, the settings form, the sign-in and the launch
/// mark — each one rendered in light and dark with fixture data.
///
/// Everything is rendered through the real screens: the view models are the
/// production ones with the existing test doubles behind their repositories, so
/// the PNG shows what the tab shows, not a copy of it.
@MainActor
final class ChromeGalleryTests: XCTestCase {

    // MARK: - Ligas

    /// The tab with a public invitation still unanswered, one private league and
    /// the free plan's cap in force: the three blocks the screen is made of.
    func testLeaguesTabGallery() async {
        let loader = FakeLeaguesDataLoader()
        loader.leaguesResult = .success([GalleryFixtures.barrioLeague])
        loader.publicLeagueStatusResult = .success(nil)

        let model = LeaguesViewModel(repository: loader)
        await model.load(userID: "user-1")

        let publicLeague = PublicLeagueViewModel(repository: loader)
        await publicLeague.load()

        let freemium = FreemiumService(anchorDate: Date(), store: GalleryPremiumStore(price: "4,99 €"))
        await freemium.refresh()

        // Every model is loaded before the sheet is built, and the session is
        // restored first: `ImageRenderer` never runs the `.task` of a view, so
        // anything awaited has to be ready before `renderGallery` is called.
        let auth = await GalleryFixtures.signedInAuth()

        // Taller than the default 390×844: the tab carries five sections, and a
        // `List` that outgrows the canvas clips silently (no assertion can catch
        // it, only the PNG).
        renderGallery("leagues", height: 1200) {
            LeaguesView(model: model, publicLeague: publicLeague)
                .environmentObject(auth)
                .environmentObject(freemium)
                // The root of the app tints with `drivyTint`; the sheet has no
                // root, so it asks for the same tint the tab gets on screen.
                .tint(Color.drivyTint)
        }
    }

    /// The weekly ranking of a private league, with the caller inside it.
    func testLeagueDetailGallery() async {
        let loader = FakeLeaguesDataLoader()
        loader.rankingOutcome = .success([
            LeagueRankingRow(rank: 1, displayName: "Marta R.", weekXP: 640, isMe: false),
            LeagueRankingRow(rank: 2, displayName: "Álvaro", weekXP: 520, isMe: false),
            LeagueRankingRow(rank: 3, displayName: "Nuria G.", weekXP: 415, isMe: true),
            LeagueRankingRow(rank: 4, displayName: "Iván", weekXP: 380, isMe: false),
            LeagueRankingRow(rank: 5, displayName: "Sofía M.", weekXP: 190, isMe: false)
        ])

        let model = LeagueRankingViewModel(leagueID: "league-1", repository: loader)
        await model.load()

        // The tab pushes this screen inside a `NavigationStack`; the sheet needs
        // the same container for the title bar the app shows.
        renderGallery("league-detail", height: 1000) {
            NavigationStack {
                LeagueDetailView(league: GalleryFixtures.barrioLeague, model: model)
            }
            .tint(Color.drivyTint)
        }
    }

    /// The public league of the week: promotion band, mid group, demotion band,
    /// the movement banner and the countdown.
    func testPublicLeagueGallery() async {
        let loader = FakeLeaguesDataLoader()
        loader.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 2, optedIn: true))
        loader.currentPublicLeagueOutcome = .success(
            PublicLeagueCurrent(groupID: "group-1", weekStart: "2026-10-26", division: 2, lastChange: 1)
        )
        loader.publicLeagueRankingOutcome = .success(GalleryFixtures.publicRanking)

        let model = PublicLeagueViewModel(repository: loader)
        await model.load()

        renderGallery("public-league", height: 1100) {
            NavigationStack {
                List {
                    PublicLeaguePanel(model: model)
                }
                .scrollContentBackground(.hidden)
                .background(Color.drivyPaper)
                .navigationTitle("Ligas")
            }
            .tint(Color.drivyTint)
        }
    }

    // MARK: - Paywall, settings, launch

    /// The paywall with the Storefront price read and the plan still Free.
    func testPaywallGallery() async {
        let freemium = FreemiumService(anchorDate: Date(), store: GalleryPremiumStore(price: "4,99 €"))
        let viewModel = PaywallViewModel(freemium: freemium)
        await viewModel.loadPrice()

        renderGallery("paywall", height: 900) {
            PaywallView(viewModel: viewModel, onClose: {})
                .tint(Color.drivyTint)
        }
    }

    /// Ajustes with a session, a visible name and the public leagues switched on.
    func testSettingsGallery() async {
        let loader = FakeLeaguesDataLoader()
        loader.publicLeagueStatusResult = .success(PublicLeagueStatus(division: 3, optedIn: true))

        let publicLeague = PublicLeagueSettingsViewModel(repository: loader)
        await publicLeague.load()

        let profile = DisplayNameViewModel(repository: FakeProfileDataLoader.withDisplayName("Marta R."))
        await profile.load(userID: "1b2c3d4e-5678-9abc-def0-111111111111")

        let auth = await GalleryFixtures.signedInAuth()

        renderGallery("settings", height: 1150) {
            SettingsView(publicLeague: publicLeague, profile: profile)
                .environmentObject(auth)
                .tint(Color.drivyTint)
        }
    }

    /// The sign-in screen: the road mark, the tagline, the Apple button.
    func testSignInGallery() async {
        renderGallery("sign-in") {
            SignInView()
                .environmentObject(AuthViewModel(authService: FakeAuthService()))
        }
    }

    /// The launch mark, drawn on the screen it fills in the app.
    func testLaunchGallery() async {
        renderGallery("launch") {
            LaunchView()
        }
    }
}

// MARK: - The StoreKit double of the galleries

/// A `PremiumEntitlementProviding` with no StoreKit: the paywall and the freemium
/// gate render the plan and the price the gallery asks for.
///
/// Written here instead of reusing `PaywallViewModel.preview(plan:)` because that
/// fixture only exists in `#if DEBUG`; the gallery must compile whatever build
/// configuration the runner picks.
private final class GalleryPremiumStore: PremiumEntitlementProviding {

    private let price: String?

    private let entitlements: [PremiumEntitlement]

    init(price: String?, entitlements: [PremiumEntitlement] = []) {
        self.price = price
        self.entitlements = entitlements
    }

    func activeEntitlements() async -> [PremiumEntitlement] {
        entitlements
    }

    func premiumDisplayPrice() async -> String? {
        price
    }

    func purchase() async throws -> [PremiumEntitlement] {
        entitlements
    }

    func restore() async throws -> [PremiumEntitlement] {
        entitlements
    }

    func entitlementUpdates() -> AsyncStream<[PremiumEntitlement]> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

// MARK: - Standings lanes (pure rule of S5)

/// The rule behind the movement lanes of the public standings: one dashed lane
/// mark per zone, nothing else added and nothing lost.
final class LeagueStandingsLaneTests: XCTestCase {

    func testNoRowsNoItems() {
        XCTAssertTrue(LeagueStandingsLanes.items(for: []).isEmpty)
    }

    func testRowsWithoutZoneStayAlone() {
        let rows = [
            PublicLeagueRankingRow(place: 1, displayName: "Marta R.", weekXP: 640, zone: nil, isMe: false),
            PublicLeagueRankingRow(place: 2, displayName: "Álvaro", weekXP: 520, zone: nil, isMe: true)
        ]

        XCTAssertEqual(
            LeagueStandingsLanes.items(for: rows),
            rows.map { LeagueStandingsItem.row($0) }
        )
    }

    func testPromotionBandIsAnnouncedOnce() {
        let promotion = PublicLeagueRankingRow(place: 1, displayName: "Marta R.", weekXP: 640, zone: .promotion, isMe: false)
        let second = PublicLeagueRankingRow(place: 2, displayName: "Álvaro", weekXP: 520, zone: .promotion, isMe: false)
        let plain = PublicLeagueRankingRow(place: 3, displayName: "Nuria G.", weekXP: 415, zone: nil, isMe: false)

        XCTAssertEqual(
            LeagueStandingsLanes.items(for: [promotion, second, plain]),
            [.divider(.promotion), .row(promotion), .row(second), .row(plain)]
        )
    }

    func testBothBandsGetTheirOwnLaneMarkInOrder() {
        let items = LeagueStandingsLanes.items(for: GalleryFixtures.publicRanking)

        let dividers = items.compactMap { item -> PublicLeagueZone? in
            if case .divider(let zone) = item { return zone }
            return nil
        }
        XCTAssertEqual(dividers, [.promotion, .demotion])
    }

    func testNothingIsDroppedOrReordered() {
        let rows = GalleryFixtures.publicRanking
        let items = LeagueStandingsLanes.items(for: rows)

        let listed = items.compactMap { item -> PublicLeagueRankingRow? in
            if case .row(let row) = item { return row }
            return nil
        }
        XCTAssertEqual(listed, rows)
        XCTAssertEqual(items.count, rows.count + 2)
    }

    func testDividerFollowsTheBandEvenWhenThePayloadIsOutOfOrder() {
        // A zone is announced where its first row appears, wherever that is: the
        // client trusts `zone` and never recomputes the bands (S2).
        let demotion = PublicLeagueRankingRow(place: 1, displayName: "Hugo", weekXP: 120, zone: .demotion, isMe: false)
        let promotion = PublicLeagueRankingRow(place: 2, displayName: "Marta R.", weekXP: 640, zone: .promotion, isMe: false)

        XCTAssertEqual(
            LeagueStandingsLanes.items(for: [demotion, promotion]),
            [.divider(.demotion), .row(demotion), .divider(.promotion), .row(promotion)]
        )
    }

    func testItemIdsAreUniqueAcrossOneStandings() {
        let items = LeagueStandingsLanes.items(for: GalleryFixtures.publicRanking)
        let ids = items.map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count, "ForEach identity collides inside one standings list")
    }
}

// MARK: - Tab bar (pure rule of S4/S5)

/// The four tabs of the road: same titles, same order, and none of the fitness
/// symbols the redesign retired (S4).
final class DrivyTabTests: XCTestCase {

    func testTabsInOrder() {
        XCTAssertEqual(DrivyTab.allCases, [.hoy, .camino, .ligas, .ajustes])
    }

    func testTabTitlesAreTheCopyTheAppStartedWith() {
        XCTAssertEqual(DrivyTab.allCases.map(\.title), ["Hoy", "Camino", "Ligas", "Ajustes"])
    }

    func testTabSymbolsAreTheRoadSet() {
        XCTAssertEqual(
            DrivyTab.allCases.map(\.symbol),
            ["road.lanes", "signpost.right", "list.number", "gearshape"]
        )
    }

    func testNoTabKeepsARetiredSymbol() {
        // S4: no trophy, no speedometer, no star, no flame in the shell.
        for tab in DrivyTab.allCases {
            for retired in ["trophy", "speedometer", "star", "flame", "sparkles", "snowflake"] {
                XCTAssertFalse(
                    tab.symbol.contains(retired),
                    "tab \(tab.rawValue) still uses the retired symbol \(tab.symbol)"
                )
            }
        }
    }

    func testEveryTabSymbolExistsBeforeTheDeploymentTarget() {
        // `UIImage(systemName:)` returns nil on a system without the symbol: at a
        // 17.0 target every tab icon must already be there, or the tab is blank.
        for tab in DrivyTab.allCases {
            XCTAssertNotNil(
                UIImage(systemName: tab.symbol),
                "symbol \(tab.symbol) of tab \(tab.rawValue) does not resolve on this system"
            )
        }
    }
}

// MARK: - Fixture helpers

/// The data the galleries draw with, outside any actor: the pure lane tests read
/// the same standings the PNG shows, so a change to the fixture is a change to
/// what is asserted.
///
/// It is a file-level enum and not a `static` of the `@MainActor` test class
/// because the rule tests are not main-actor isolated.
private enum GalleryFixtures {

    /// A league with the shape the RPC answers: eight-symbol code, no O and no I.
    static var barrioLeague: LeagueRecord {
        LeagueRecord(
            id: "league-1",
            name: "Los del barrio",
            ownerID: "user-1",
            inviteCode: "ABC23456"
        )
    }

    /// A group of the public league: two rows that promote, five that stay, three
    /// that drop, the caller in the middle of it.
    static var publicRanking: [PublicLeagueRankingRow] {
        [
            PublicLeagueRankingRow(place: 1, displayName: "Marta R.", weekXP: 640, zone: .promotion, isMe: false),
            PublicLeagueRankingRow(place: 2, displayName: "Álvaro", weekXP: 520, zone: .promotion, isMe: false),
            PublicLeagueRankingRow(place: 3, displayName: "Nuria G.", weekXP: 415, zone: nil, isMe: false),
            PublicLeagueRankingRow(place: 4, displayName: "Iván", weekXP: 380, zone: nil, isMe: false),
            PublicLeagueRankingRow(place: 5, displayName: "Sofía M.", weekXP: 300, zone: nil, isMe: true),
            PublicLeagueRankingRow(place: 6, displayName: "Diego", weekXP: 260, zone: nil, isMe: false),
            PublicLeagueRankingRow(place: 7, displayName: "Elena V.", weekXP: 210, zone: nil, isMe: false),
            PublicLeagueRankingRow(place: 8, displayName: "Hugo", weekXP: 120, zone: .demotion, isMe: false),
            PublicLeagueRankingRow(place: 9, displayName: "Carla P.", weekXP: 90, zone: .demotion, isMe: false),
            PublicLeagueRankingRow(place: 10, displayName: "Luis", weekXP: 40, zone: .demotion, isMe: false)
        ]
    }

    /// An auth model that already holds a session, so the account rows have data.
    ///
    /// `restoreSession()` is awaited before the sheet is built: `ImageRenderer`
    /// never runs the `.task` of a view, so the session has to be there already.
    @MainActor
    static func signedInAuth() async -> AuthViewModel {
        let service = FakeAuthService()
        service.restoredUser = UserSummary(
            id: "1b2c3d4e-5678-9abc-def0-111111111111",
            email: "marta@example.com",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let auth = AuthViewModel(authService: service)
        await auth.restoreSession()
        return auth
    }
}

private extension FakeProfileDataLoader {

    /// A profile loader that answers with a stored name, for the settings gallery.
    static func withDisplayName(_ name: String) -> FakeProfileDataLoader {
        let loader = FakeProfileDataLoader()
        loader.displayNameResult = .success(name)
        return loader
    }
}

/// S8: the tab bar (T5) rendered with the real tabs, titles and symbols.
@MainActor
final class TabBarGalleryTests: XCTestCase {

    func testTabBarGallery() {
        DrivyAppearance.configure()
        renderGallery("tab-bar") {
            TabView {
                ForEach(DrivyTab.allCases, id: \.self) { tab in
                    Color.drivyPaper
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                }
            }
        }
    }
}
