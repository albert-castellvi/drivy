import SwiftUI

@main
struct DrivyApp: App {

    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.restoreSession() }
        }
    }
}
