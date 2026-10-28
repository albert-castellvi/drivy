import SwiftUI

/// Tab "Ajustes": visible name, account, public leagues, sign out and app metadata.
///
/// A native `Form` stays: settings are the one screen where the system layout is
/// the right one. The road design only changes its surface (S3): the paper of the
/// screen, raised rows, kicker headers, and the tint the root already sets.
struct SettingsView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Opt-in switch of the public leagues (S5). Same decision as the invitation
    /// block of the Ligas tab.
    @StateObject private var publicLeague: PublicLeagueSettingsViewModel

    /// Visible name of the profile (S2).
    @StateObject private var profile: DisplayNameViewModel

    /// Whether the name editor sheet is on screen.
    @State private var isEditingDisplayName = false

    init() {
        _publicLeague = StateObject(wrappedValue: PublicLeagueSettingsViewModel())
        _profile = StateObject(wrappedValue: DisplayNameViewModel())
    }

    /// Same screen over already-built models (S8): the gallery renders the real
    /// rows with fixture values. The app keeps the no-argument initialiser.
    init(publicLeague: PublicLeagueSettingsViewModel, profile: DisplayNameViewModel) {
        _publicLeague = StateObject(wrappedValue: publicLeague)
        _profile = StateObject(wrappedValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                displayNameSection
                accountSection
                publicLeagueSection

                Section {
                    Group {
                        Button("Cerrar sesión", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                        .font(.drivyBody)
                    }
                    .settingsRow()
                }

                Section {
                    Group {
                        LabeledContent("Versión", value: AppInfo.versionText)
                        LabeledContent("Proveedor de acceso", value: "Sign in with Apple")
                            .font(.drivyBody)
                    }
                    .settingsRow()
                } header: {
                    settingsHeader("Acerca de")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.drivyPaper)
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
            Group {
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
                        .font(.drivyBody)
                        .disabled(profile.isLoading)
                    } else {
                        Button("Cambiar nombre") {
                            profile.resetDraft()
                            isEditingDisplayName = true
                        }
                        .font(.drivyBody)
                    }
                }

                if let errorMessage = profile.errorMessage {
                    Text(errorMessage)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyAlertText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsRow()
        } header: {
            settingsHeader("Identidad")
        } footer: {
            Text(
                "Es el nombre que ven los demás conductores en las ligas, "
                    + "también en las públicas. Tu email no se muestra nunca."
            )
            .font(.drivyFootnote)
            .foregroundStyle(Color.drivyInkMuted)
        }
    }

    private var displayNameEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        TextField("Nombre visible", text: $profile.draft)
                            .font(.drivyBody)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    .settingsRow()
                } footer: {
                    Text("Entre 1 y 30 caracteres. Es el nombre que aparecerá en las ligas.")
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyInkMuted)
                }

                if let errorMessage = profile.errorMessage {
                    Section {
                        Group {
                            Text(errorMessage)
                                .font(.drivyFootnote)
                                .foregroundStyle(Color.drivyAlertText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .settingsRow()
                    }
                }

                Section {
                    Group {
                        Button("Guardar") {
                            saveDisplayName()
                        }
                        .font(.drivyBody)
                        .disabled(profile.isSaving)

                        Button("Cancelar", role: .cancel) {
                            isEditingDisplayName = false
                        }
                        .font(.drivyBody)
                    }
                    .settingsRow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.drivyPaper)
            .navigationTitle("Nombre visible")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            Group {
                if let user = auth.signedInUser {
                    LabeledContent("Identificador", value: user.shortIdentifier)

                    if let email = user.email {
                        LabeledContent("Email", value: email)
                    }
                } else {
                    Text("No hay ninguna sesión activa.")
                        .font(.drivyBody)
                        .foregroundStyle(Color.drivyInkMuted)
                }
            }
            .settingsRow()
        } header: {
            settingsHeader("Cuenta")
        }
    }

    // MARK: - Public leagues (S5)

    /// S5: participating is opt-in, and the decision lives in the profile row of
    /// `public.public_league_entries`.
    private var publicLeagueSection: some View {
        Section {
            Group {
                Toggle(
                    "Participar en ligas públicas",
                    isOn: Binding(
                        get: { publicLeague.isEnabled },
                        set: { newValue in
                            Task { _ = await publicLeague.setEnabled(newValue) }
                        }
                    )
                )
                .font(.drivyBody)
                .disabled(publicLeague.isLoading || publicLeague.isSaving)

                if let errorMessage = publicLeague.errorMessage {
                    Text(errorMessage)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyAlertText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsRow()
        } header: {
            settingsHeader("Ligas públicas")
        } footer: {
            Text("Compite por XP con conductores de tu nivel, en grupos de unos 30 repartidos por divisiones. En el grupo solo se ve tu nombre visible.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
        }
    }

    // MARK: - Chrome of the Form

    /// The small label above a section: the kicker role in the muted ink (S3).
    private func settingsHeader(_ title: String) -> some View {
        Text(title)
            .font(.drivyKicker)
            .foregroundStyle(Color.drivyInkMuted)
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

private extension View {

    /// One row surface of the settings Form: `paperRaised` on the paper of the
    /// screen, with its hairline (S3). Applied to a section, it covers its rows.
    func settingsRow() -> some View {
        listRowBackground(Color.drivyPaperRaised)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
