import SwiftUI

/// Tab shell of the MVP: Hoy (Today), Camino (Path), Ligas (Leagues), Ajustes
/// (Settings).
///
/// Same four tabs, same titles and order either way: iOS 18 and later describe
/// them with the current `Tab` API, iOS 17 keeps `.tabItem`. Both paths read
/// their title and their symbol from `DrivyTab`, so the fallback cannot drift
/// from the modern one.
///
/// The symbols are the road vocabulary of S5 instead of the fitness kit:
/// `road.lanes` for the day that is a stretch of road, `signpost.right` for the
/// path of habits, `list.number` for a standings list, `gearshape` for the
/// settings that were always a gear. None of them is the trophy or the
/// speedometer of a gym app (S4).
///
/// Camino sits between Hoy and Ligas (S3): it is the habit path of the loop, and
/// the public leagues are what the path feeds with XP.
struct MainTabView: View {

    var body: some View {
        if #available(iOS 18, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    /// Current tab API (`Tab` replaced `.tabItem`). It is also what the iOS 26
    /// design reads from, so the shell follows the system look on 26 without
    /// hand-built chrome; on iOS 17/18/25 the look is the same as before.
    @available(iOS 18, *)
    private var modernTabs: some View {
        TabView {
            Tab(DrivyTab.hoy.title, systemImage: DrivyTab.hoy.symbol) {
                TodayView()
            }

            Tab(DrivyTab.camino.title, systemImage: DrivyTab.camino.symbol) {
                PathView()
            }

            Tab(DrivyTab.ligas.title, systemImage: DrivyTab.ligas.symbol) {
                LeaguesView()
            }

            Tab(DrivyTab.ajustes.title, systemImage: DrivyTab.ajustes.symbol) {
                SettingsView()
            }
        }
    }

    /// iOS 17 fallback: soft-deprecated `.tabItem`, kept because the deployment
    /// target is still 17.0. Same titles, same symbols, same order.
    private var legacyTabs: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label(DrivyTab.hoy.title, systemImage: DrivyTab.hoy.symbol)
                }

            PathView()
                .tabItem {
                    Label(DrivyTab.camino.title, systemImage: DrivyTab.camino.symbol)
                }

            LeaguesView()
                .tabItem {
                    Label(DrivyTab.ligas.title, systemImage: DrivyTab.ligas.symbol)
                }

            SettingsView()
                .tabItem {
                    Label(DrivyTab.ajustes.title, systemImage: DrivyTab.ajustes.symbol)
                }
        }
    }
}

/// The two values every tab has: its Spanish title and its symbol.
///
/// One definition for both presentation paths of `MainTabView`, so the copy is
/// written once and a test can walk the four tabs instead of the shell.
enum DrivyTab: String, CaseIterable {

    case hoy
    case camino
    case ligas
    case ajustes

    /// Tab titles, byte-identical to the copy the redesign started with (S6).
    var title: String {
        switch self {
        case .hoy:
            return "Hoy"
        case .camino:
            return "Camino"
        case .ligas:
            return "Ligas"
        case .ajustes:
            return "Ajustes"
        }
    }

    /// SF Symbols that ship with iOS 16 or earlier (S4, S5): every device the
    /// 17.0 deployment target runs on has all four.
    var symbol: String {
        switch self {
        case .hoy:
            return "road.lanes"
        case .camino:
            return "signpost.right"
        case .ligas:
            return "list.number"
        case .ajustes:
            return "gearshape"
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(FreemiumService(anchorDate: Date()))
        .environmentObject(FreemiumSessionCoordinator())
}
