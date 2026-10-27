import SwiftUI

/// Tab shell of the MVP: Hoy (Today), Ligas (Leagues), Ajustes (Settings).
///
/// Same three tabs, same titles, symbols and order either way: iOS 18 and later
/// describe them with the current `Tab` API, iOS 17 keeps `.tabItem`.
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
            Tab("Hoy", systemImage: "speedometer") {
                TodayView()
            }

            Tab("Ligas", systemImage: "trophy") {
                LeaguesView()
            }

            Tab("Ajustes", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }

    /// iOS 17 fallback: soft-deprecated `.tabItem`, kept because the deployment
    /// target is still 17.0.
    private var legacyTabs: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Hoy", systemImage: "speedometer")
                }

            LeaguesView()
                .tabItem {
                    Label("Ligas", systemImage: "trophy")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(FreemiumService(anchorDate: Date()))
        .environmentObject(FreemiumSessionCoordinator())
}
