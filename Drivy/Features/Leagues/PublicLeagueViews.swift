import SwiftUI

/// Invitation card of the public league (S5, L9).
///
/// Shown at the top of the Ligas tab only while the user never answered the
/// question: answering "Ahora no" stores `opted_in = false` and the card goes
/// away, so the app asks exactly once.
///
/// Nothing here invites the user to drive: the competition is on XP, which comes
/// from driving well and from lessons (S4).
struct PublicLeagueInvitationCard: View {

    @ObservedObject var model: PublicLeagueViewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Liga pública", systemImage: "trophy.fill")
                    .font(.headline)

                Text("Compite por XP con unos 30 conductores de tu nivel. En el grupo solo se ve tu nombre visible.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                Button {
                    Task { _ = await model.join() }
                } label: {
                    Text("Unirme")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSubmitting)

                Button {
                    Task { _ = await model.decline() }
                } label: {
                    Text("Ahora no")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Text("Puedes activarla o desactivarla cuando quieras en Ajustes.")
        }
    }
}

/// Public league of the current week (S5): division, movement banner, group
/// standings with their promotion/demotion zones, and the days left.
struct PublicLeaguePanel: View {

    @ObservedObject var model: PublicLeagueViewModel

    var body: some View {
        if model.isChangeBannerVisible {
            changeSection
        }

        standingsSection

        Section {
            Label(model.daysLeftText, systemImage: "calendar")
                .font(.subheadline)
        } footer: {
            Text("Los grupos se forman el lunes a las 00:00 y se ordenan por XP de la semana.")
        }
    }

    // MARK: - Movement banner

    private var changeSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(model.changeBannerText, systemImage: changeSymbol)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    model.dismissChangeBanner()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descartar aviso")
            }
        }
    }

    private var changeSymbol: String {
        switch model.current?.lastChange ?? 0 {
        case 1:
            return "arrow.up.circle.fill"
        case -1:
            return "arrow.down.circle.fill"
        default:
            return "equal.circle.fill"
        }
    }

    // MARK: - Standings

    private var standingsSection: some View {
        Section {
            if model.ranking.isEmpty {
                Text("Tu grupo de esta semana aún no tiene posiciones. Aparecerán en cuanto haya XP.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.ranking) { row in
                standingsRow(row)
                    .listRowBackground(highlight(for: row))
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(model.divisionTitle)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(PublicLeagueZone.promotion.explanation)
                Text(PublicLeagueZone.demotion.explanation)
            }
        }
    }

    private func standingsRow(_ row: PublicLeagueRankingRow) -> some View {
        HStack(spacing: 12) {
            Text("\(row.place)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, alignment: .leading)

            Text(row.displayName)
                .font(.subheadline.weight(row.isMe ? .bold : .regular))

            Spacer(minLength: 0)

            if let zone = row.zone {
                Image(systemName: zone.symbolName)
                    .font(.caption)
                    .foregroundStyle(zone == .promotion ? Color.green : Color.red)
                    .accessibilityLabel(zone.label)
            }

            Text(row.xpText)
                .font(.headline.monospacedDigit())
        }
        .foregroundStyle(row.isMe ? Color.accentColor : Color.primary)
    }

    /// Current user marked on the row itself, so the eye finds it without
    /// scanning names. The server marks the row (S2): the client no longer knows
    /// anybody's uuid, not even its own inside the standings.
    private func highlight(for row: PublicLeagueRankingRow) -> Color? {
        row.isMe ? Color.accentColor.opacity(0.12) : nil
    }
}

#Preview("Invitación") {
    List {
        PublicLeagueInvitationCard(model: PublicLeagueViewModel())
    }
}

#Preview("Liga pública") {
    List {
        PublicLeaguePanel(model: PublicLeagueViewModel())
    }
}
