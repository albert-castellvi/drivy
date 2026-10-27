import SwiftUI

/// Shown while the persisted session is being read from the Keychain.
struct LaunchView: View {

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 44, weight: .semibold))

            Text(DrivyConfig.appDisplayName)
                .font(.largeTitle.bold())

            ProgressView()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown while the Apple sheet / token exchange is in flight.
struct AuthenticatingView: View {

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Conectando con tu cuenta…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LaunchView()
}
