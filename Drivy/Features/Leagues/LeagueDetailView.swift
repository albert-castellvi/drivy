import SwiftUI

/// One private league (S5): the weekly XP ranking plus the invite link that
/// brings friends in.
///
/// The ranking is the same ranked list as the public standings (S5): position,
/// name, XP trailing, and a 3 pt tint bar on the caller's own row.
struct LeagueDetailView: View {

    let league: LeagueRecord

    @StateObject private var model: LeagueRankingViewModel

    init(league: LeagueRecord) {
        self.league = league
        _model = StateObject(wrappedValue: LeagueRankingViewModel(leagueID: league.id))
    }

    /// Same screen over an already-built ranking model (S8): the gallery renders
    /// the list with fixture rows instead of waiting for a network that never
    /// answers in a test host. The tab uses the `league`-only initialiser above.
    init(league: LeagueRecord, model: LeagueRankingViewModel) {
        self.league = league
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        List {
            rankingSection
            inviteSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.drivyPaper)
        .navigationTitle(league.name)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    // MARK: - Ranking

    private var rankingSection: some View {
        Section {
            if model.rows.isEmpty && !model.isLoading {
                Text("Aún no hay XP esta semana. En cuanto alguien puntúe, aparece aquí.")
                    .font(.drivyBody)
                    .foregroundStyle(Color.drivyInkMuted)
                    .listRowBackground(Color.drivyPaper)
            }

            ForEach(model.rows) { row in
                LeagueStandingsRow(
                    position: row.rank,
                    displayName: row.displayName,
                    xpText: row.xpText,
                    isMe: row.isMe
                )
                .listRowBackground(Color.drivyPaper)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyAlertText)
                    .listRowBackground(Color.drivyPaper)
            }
        } header: {
            Text(model.weekStartLabel.isEmpty ? "Semana actual" : "Semana del \(model.weekStartLabel)")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
        } footer: {
            Text("Clasificación por XP de la semana. El XP se gana conduciendo bien y con lecciones, nunca por conducir más.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
        }
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
                        .font(.drivyBody)
                }
                .listRowBackground(Color.drivyPaper)
            }

            LabeledContent("Código", value: league.inviteCode)
                .font(.drivyBody)
                .listRowBackground(Color.drivyPaper)
        } header: {
            Text("Invitar")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
        } footer: {
            Text("Código de 8 caracteres, hasta 25 amigos por liga. El enlace abre la app y une a quien lo recibe.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
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
                inviteCode: "ABC23456"
            )
        )
    }
}
