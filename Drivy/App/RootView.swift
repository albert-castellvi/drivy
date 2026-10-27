import SwiftUI

/// Root of the shell: picks the screen that matches the auth state.
struct RootView: View {

    @EnvironmentObject private var auth: AuthViewModel

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
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.state)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
