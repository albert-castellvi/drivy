import SwiftUI

/// Tab "Ajustes": account, public leagues, sign out and app metadata.
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Opt-in switch of the public leagues (S5). Same decision as the invitation
    /// card of the Ligas tab.
    @StateObject private var publicLeague = PublicLeagueSettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                publicLeagueSection

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
            .task { await publicLeague.load() }
        }
    }

    private var accountSection: some View {
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
    }

    /// S5: participating is opt-in, and the decision lives in the profile row of
    /// `public.public_league_entries`.
    private var publicLeagueSection: some View {
        Section {
            Toggle(
                "Participar en ligas públicas",
                isOn: Binding(
                    get: { publicLeague.isEnabled },
                    set: { newValue in
                        Task { _ = await publicLeague.setEnabled(newValue) }
                    }
                )
            )
            .disabled(publicLeague.isLoading || publicLeague.isSaving)

            if let errorMessage = publicLeague.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Ligas públicas")
        } footer: {
            Text("Compite por XP con conductores de tu nivel, en grupos de unos 30 repartidos por divisiones. En el grupo solo se ve tu nombre visible.")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
