import SwiftUI

/// Tab "Ajustes": visible name, account, public leagues, sign out and app metadata.
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Opt-in switch of the public leagues (S5). Same decision as the invitation
    /// card of the Ligas tab.
    @StateObject private var publicLeague = PublicLeagueSettingsViewModel()

    /// Visible name of the profile (S2).
    @StateObject private var profile = DisplayNameViewModel()

    /// Whether the name editor sheet is on screen.
    @State private var isEditingDisplayName = false

    var body: some View {
        NavigationStack {
            Form {
                displayNameSection
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
            .task(id: auth.signedInUser?.id) { await loadDisplayName() }
            .sheet(isPresented: $isEditingDisplayName) {
                displayNameEditor
            }
        }
    }

    // MARK: - Visible name (S2)

    /// S2: the name other drivers read in a league is visible and editable here.
    /// It is a pseudonym the app generated, never the name of the Apple account,
    /// and the email and the id of the row are the only other things the screen
    /// shows of the profile.
    private var displayNameSection: some View {
        Section {
            LabeledContent("Nombre visible", value: profile.displayName ?? "—")

            // Nothing to read or edit without a session; the account section below
            // already says so, and a retry would be a button that does nothing.
            if auth.signedInUser != nil {
                if profile.displayName == nil {
                    // A failed read must not leave the field unusable: the retry is
                    // the only way back in without relaunching the app.
                    Button("Reintentar") {
                        Task { await loadDisplayName() }
                    }
                    .disabled(profile.isLoading)
                } else {
                    Button("Cambiar nombre") {
                        profile.resetDraft()
                        isEditingDisplayName = true
                    }
                }
            }

            if let errorMessage = profile.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Identidad")
        } footer: {
            Text(
                "Es el nombre que ven los demás conductores en las ligas, "
                    + "también en las públicas. Tu email no se muestra nunca."
            )
        }
    }

    private var displayNameEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre visible", text: $profile.draft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Entre 1 y 30 caracteres. Es el nombre que aparecerá en las ligas.")
                }

                if let errorMessage = profile.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Button("Guardar") {
                        saveDisplayName()
                    }
                    .disabled(profile.isSaving)

                    Button("Cancelar", role: .cancel) {
                        isEditingDisplayName = false
                    }
                }
            }
            .navigationTitle("Nombre visible")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Account

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

    // MARK: - Public leagues (S5)

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

    // MARK: - Actions

    @MainActor
    private func loadDisplayName() async {
        guard let userID = auth.signedInUser?.id else { return }
        await profile.load(userID: userID)
    }

    @MainActor
    private func saveDisplayName() {
        guard let userID = auth.signedInUser?.id else { return }

        Task {
            let saved = await profile.save(userID: userID)
            if saved {
                isEditingDisplayName = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
