import SwiftUI

/// Tab shell of the MVP: Hoy (Today), Ligas (Leagues), Ajustes (Settings).
struct MainTabView: View {

    var body: some View {
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
