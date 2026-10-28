import SwiftUI

/// Sign in with Apple is the only way in (S10: Apple requires it when the app
/// offers any social login, and it keeps the backend free of passwords).
struct SignInView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Failure copy produced by the view model, if the last attempt failed.
    private var failureMessage: String? {
        if case .failed(let message) = auth.state {
            return message
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // The road and the wordmark: the same identity the launch screen
            // shows, so the app looks like itself from the first second (S5).
            RoadIdentityMark()

            Text("Convierte cada trayecto en una partida. Tu Driver Score, tu racha y tus ligas, en un solo sitio.")
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                AppleSignInButton {
                    Task { await auth.signInWithApple() }
                }
                .frame(height: 52)

                if let failureMessage = failureMessage {
                    Text(failureMessage)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyAlertText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Al continuar aceptas que tratemos los datos de tus trayectos para calcular tu Driver Score. No vendemos tus datos.")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.drivyPaper)
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthViewModel())
}
