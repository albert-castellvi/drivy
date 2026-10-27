import SwiftUI

/// Tab "Ligas" (S7): the user's leagues, creation and join by code.
struct LeaguesView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var model = LeaguesViewModel()
    @State private var isCreatingLeague = false
    @State private var joinCode = ""

    var body: some View {
        NavigationStack {
            List {
                leaguesSection
                joinSection
                createSection
            }
            .navigationTitle("Ligas")
            .refreshable { await reload() }
            .task(id: auth.signedInUser?.id) { await reload() }
            .sheet(isPresented: $isCreatingLeague) {
                CreateLeagueSheet(model: model, userID: signedInUserID)
            }
        }
    }

    // MARK: - Sections

    private var leaguesSection: some View {
        Section("Tus ligas") {
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

    private var createSection: some View {
        Section {
            Button {
                isCreatingLeague = true
            } label: {
                Label("Crear liga", systemImage: "plus.circle.fill")
            }
            .disabled(model.isCreating)
        } footer: {
            Text("Compite con hasta 25 amigos por el mejor Driver Score de la semana.")
        }
    }

    // MARK: - Data

    private var signedInUserID: String {
        auth.signedInUser?.id ?? ""
    }

    private func reload() async {
        guard let userID = auth.signedInUser?.id else { return }
        await model.load(userID: userID)
    }

    private func join() async {
        guard let userID = auth.signedInUser?.id else { return }
        let joined = await model.joinLeague(code: joinCode, userID: userID)
        if joined {
            joinCode = ""
        }
    }
}

/// Sheet that creates a league: a name, and the invite code is generated.
private struct CreateLeagueSheet: View {

    @ObservedObject var model: LeaguesViewModel

    let userID: String

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
                            let created = await model.createLeague(name: name, userID: userID)
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
}
