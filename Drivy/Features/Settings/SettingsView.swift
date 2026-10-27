import SwiftUI

/// Tab "Ajustes": account, sign out and app metadata.
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    if let user = auth.signedInUser {
                        LabeledContent("Identificador", value: user.shortIdentifier)

                        if let email = user.email {
                            LabeledContent("Email", value: email)
                        }
                    } else {
                        Text("No hay ninguna sesión activa.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: AppInfo.versionText)
                    LabeledContent("Proveedor de acceso", value: "Sign in with Apple")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
