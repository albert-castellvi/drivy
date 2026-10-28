import SwiftUI

/// Tab "Ligas" (S5): the public league of the week, the user's private leagues,
/// creation and join by code.
///
/// Order matters: the public league is the main competition, the private ones
/// are the extra the spec keeps ("Las ligas privadas se mantienen como extra").
///
/// S9: the free plan allows one private league, created or joined, so both
/// actions go through `LeagueLimitGate` and a blocked action offers the paywall
/// instead. The public league is not affected by that cap.
struct LeaguesView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Plan and gating rules of the session (S9), owned by `RootView`.
    @EnvironmentObject private var freemium: FreemiumService

    @StateObject private var model = LeaguesViewModel()

    /// Public league state (S5): undecided, opted in or opted out.
    @StateObject private var publicLeague = PublicLeagueViewModel()

    @State private var activeSheet: ActiveSheet?
    @State private var joinCode = ""

    private enum ActiveSheet: String, Identifiable {
        case createLeague
        case paywall

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                publicLeagueSections
                leaguesSection
                limitSection
                joinSection
                createSection
            }
            .navigationTitle("Ligas")
            .refreshable { await reload() }
            .task(id: auth.signedInUser?.id) { await reload() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .createLeague:
                    CreateLeagueSheet(
                        model: model,
                        userID: signedInUserID,
                        access: freemium.access
                    )
                case .paywall:
                    PaywallPresenter(freemium: freemium)
                        .makePaywallView(onClose: { activeSheet = nil })
                }
            }
        }
    }

    /// Whether the plan in force blocks another league (S9).
    private var isLeagueLimitReached: Bool {
        model.isLeagueLimitReached(access: freemium.access)
    }

    // MARK: - Sections

    /// S5, L9: the invitation while the question is unanswered, the group of the
    /// week once opted in, and nothing at all after an explicit "no".
    @ViewBuilder
    private var publicLeagueSections: some View {
        switch publicLeague.decision {
        case .undecided:
            PublicLeagueInvitationCard(model: publicLeague)
        case .optedIn:
            PublicLeaguePanel(
                model: publicLeague,
                currentUserID: auth.signedInUser?.id
            )
        case .optedOut:
            EmptyView()
        }
    }

    private var leaguesSection: some View {
        Section("Tus ligas privadas") {
            if model.leagues.isEmpty && !model.isLoading {
                Text("Aún no estás en ninguna liga. Crea una o únete con un código.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.leagues) { league in
                NavigationLink {
                    LeagueDetailView(league: league)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(league.name)
                            .font(.headline)

                        Text("Código \(league.inviteCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var joinSection: some View {
        Section {
            TextField("Código o enlace de invitación", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit { Task { await join() } }

            Button {
                Task { await join() }
            } label: {
                if model.isJoining {
                    ProgressView()
                } else {
                    Text("Unirme a una liga")
                }
            }
            .disabled(model.isJoining)

            if let joinErrorMessage = model.joinErrorMessage {
                Text(joinErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Unirse")
        } footer: {
            Text("Pega el código de 6 caracteres o el enlace que te hayan enviado.")
        }
    }

    /// S9: shown while the free plan's one-league cap is in force, so the cap is
    /// never a silent refusal.
    @ViewBuilder
    private var limitSection: some View {
        if isLeagueLimitReached {
            Section {
                Label(LeagueLimitGate.limitMessage, systemImage: "lock.fill")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    activeSheet = .paywall
                } label: {
                    Label(PaywallCopy.title, systemImage: "star.fill")
                }
            } header: {
                Text("Plan Free")
            }
        }
    }

    private var createSection: some View {
        Section {
            Button {
                guard !isLeagueLimitReached else {
                    activeSheet = .paywall
                    return
                }
                activeSheet = .createLeague
            } label: {
                Label("Crear liga privada", systemImage: "plus.circle.fill")
            }
            .disabled(model.isCreating)
        } footer: {
            Text("Compite con hasta 25 amigos por el mayor XP de la semana. El XP se gana conduciendo bien y con lecciones, nunca por conducir más.")
        }
    }

    // MARK: - Data

    private var signedInUserID: String {
        auth.signedInUser?.id ?? ""
    }

    private func reload() async {
        guard let userID = auth.signedInUser?.id else { return }
        await publicLeague.load()
        await model.load(userID: userID)
    }

    private func join() async {
        guard let userID = auth.signedInUser?.id else { return }

        // S9: the free plan's cap offers the paywall instead of a failed request.
        guard !isLeagueLimitReached else {
            activeSheet = .paywall
            return
        }

        let joined = await model.joinLeague(code: joinCode, userID: userID, access: freemium.access)
        if joined {
            joinCode = ""
        }
    }
}

/// Sheet that creates a league: a name, and the invite code is generated.
private struct CreateLeagueSheet: View {

    @ObservedObject var model: LeaguesViewModel

    let userID: String

    /// S9 snapshot, passed through so the sheet gates with the same rules as the tab.
    let access: FreemiumAccess?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre de la liga", text: $name)
                        .autocorrectionDisabled()

                    if let createErrorMessage = model.createErrorMessage {
                        Text(createErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Te daremos un código de 6 caracteres para invitar a tus amigos.")
                }
            }
            .navigationTitle("Nueva liga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        Task {
                            let created = await model.createLeague(
                                name: name,
                                userID: userID,
                                access: access
                            )
                            if created {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    LeaguesView()
        .environmentObject(AuthViewModel())
        .environmentObject(FreemiumService(anchorDate: Date()))
}
