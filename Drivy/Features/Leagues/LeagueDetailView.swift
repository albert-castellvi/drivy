import SwiftUI

/// One league (S7): the weekly ranking plus the invite link that brings friends in.
struct LeagueDetailView: View {

    let league: LeagueRecord

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var model: LeagueRankingViewModel

    init(league: LeagueRecord) {
        self.league = league
        _model = StateObject(wrappedValue: LeagueRankingViewModel(leagueID: league.id))
    }

    var body: some View {
        List {
            rankingSection
            inviteSection
        }
        .navigationTitle(league.name)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    // MARK: - Ranking

    private var rankingSection: some View {
        Section {
            if model.rows.isEmpty && !model.isLoading {
                Text("Aún no hay trayectos esta semana. En cuanto alguien conduzca, aparece aquí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.rows) { row in
                rankingRow(row)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(model.weekStartLabel.isEmpty ? "Semana actual" : "Semana del \(model.weekStartLabel)")
        } footer: {
            Text("Ranking por Driver Score medio de la semana; los kilómetros desempatan.")
        }
    }

    private func rankingRow(_ row: LeagueRankingRow) -> some View {
        HStack(spacing: 12) {
            Text("\(row.rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.subheadline.weight(isCurrentUser(row) ? .bold : .regular))

                Text(DriveFormat.distance(row.totalKm))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(DriveFormat.score(row.averageScore))
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(isCurrentUser(row) ? Color.accentColor : Color.primary)
    }

    private func isCurrentUser(_ row: LeagueRankingRow) -> Bool {
        auth.signedInUser?.id == row.userID
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            if let url = LeagueInviteLink.url(forInviteCode: league.inviteCode) {
                ShareLink(
                    item: url,
                    subject: Text("Únete a mi liga en Drivy"),
                    message: Text("Abre el enlace o usa el código \(league.inviteCode).")
                ) {
                    Label("Compartir enlace de invitación", systemImage: "square.and.arrow.up")
                }
            }

            LabeledContent("Código", value: league.inviteCode)
        } header: {
            Text("Invitar")
        } footer: {
            Text("Hasta 25 amigos por liga. El enlace abre la app y une a quien lo recibe.")
        }
    }
}

#Preview {
    NavigationStack {
        LeagueDetailView(
            league: LeagueRecord(
                id: "preview",
                name: "Los del barrio",
                ownerID: "preview",
                inviteCode: "ABC234"
            )
        )
    }
    .environmentObject(AuthViewModel())
}
