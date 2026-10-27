import SwiftUI

/// Root of the shell: picks the screen that matches the auth state.
///
/// It also owns the freemium session (S9): the `FreemiumService` is created when a
/// user signs in and injected into the tabs through the environment, so every
/// screen gates with the same plan snapshot and a purchase made in one tab is seen
/// by the others.
struct RootView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var freemiumSession = FreemiumSessionCoordinator()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                LaunchView()
            case .signedOut, .failed:
                SignInView()
            case .authenticating:
                AuthenticatingView()
            case .signedIn:
                signedInContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.state)
        .task(id: auth.signedInUser?.id) { await syncFreemiumSession() }
        // S7: the reminder follows the day's progress, so it is rebuilt every time
        // the app comes back to the foreground.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, auth.signedInUser != nil else { return }
            Task { await DriveNotifications.refresh() }
        }
    }

    /// The tabs are only built once the session has a freemium service, because
    /// every gated screen reads it from the environment. Until then the launch
    /// screen stays on: it is one frame, and it never shows a plan-less shell.
    @ViewBuilder
    private var signedInContent: some View {
        if let service = freemiumSession.service {
            MainTabView()
                .environmentObject(service)
                .environmentObject(freemiumSession)
        } else {
            LaunchView()
        }
    }

    private func syncFreemiumSession() async {
        guard let user = auth.signedInUser else {
            freemiumSession.signOut()
            return
        }
        await freemiumSession.signIn(as: user)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
