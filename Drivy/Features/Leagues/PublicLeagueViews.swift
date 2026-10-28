import SwiftUI

/// Invitation block of the public league (S5, L9).
///
/// Shown at the top of the Ligas tab only while the user never answered the
/// question: answering "Ahora no" stores `opted_in = false` and the block goes
/// away, so the app asks exactly once.
///
/// It is a quiet block of the list, not a card: the road system keeps its
/// surfaces flat and lets the blue information sign carry the voice (S3).
///
/// Nothing here invites the user to drive: the competition is on XP, which comes
/// from driving well and from lessons (S4).
struct PublicLeagueInvitationCard: View {

    @ObservedObject var model: PublicLeagueViewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                // The sign is a square, not a glyph: it is centred on the line
                // instead of being hung from the text baseline, where a square
                // would sit a descender too high.
                HStack(alignment: .center, spacing: 12) {
                    RoadSign(kind: .info(systemName: "person.3"), size: RoadMetrics.minSignSize)

                    Text("Liga pública")
                        .font(.drivyHeadline)
                        .foregroundStyle(Color.drivyInk)
                }

                Text("Compite por XP con unos 30 conductores de tu nivel. En el grupo solo se ve tu nombre visible.")
                    .font(.drivyBody)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.drivyPaper)

            HStack(spacing: 12) {
                Button {
                    Task { _ = await model.join() }
                } label: {
                    Text("Unirme")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // Filled with the sign blue: the light dark-mode tint is for text, not fills.
                .tint(Color.drivySignBlue)
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
            .listRowBackground(Color.drivyPaper)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyAlertText)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.drivyPaper)
            }
        } footer: {
            Text("Puedes activarla o desactivarla cuando quieras en Ajustes.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
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
            Text(model.daysLeftText)
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
                .padding(.vertical, 2)
                .listRowBackground(Color.drivyPaper)
        } footer: {
            Text("Los grupos se forman el lunes a las 00:00 y se ordenan por XP de la semana.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
        }
    }

    // MARK: - Movement banner

    private var changeSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: changeSymbol)
                    .imageScale(.medium)
                    .foregroundStyle(changeTint)
                    .accessibilityHidden(true)

                Text(model.changeBannerText)
                    .font(.drivyBodyStrong)
                    .foregroundStyle(Color.drivyInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    model.dismissChangeBanner()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.drivyInkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descartar aviso")
            }
            .listRowBackground(Color.drivyPaper)
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

    /// Up is a good move, down is a bad one: the same two colours the zone
    /// arrows of the standings use (S3), never the red of a sign shape.
    private var changeTint: Color {
        switch model.current?.lastChange ?? 0 {
        case 1:
            return Color.drivyGo
        case -1:
            return Color.drivyAlertText
        default:
            return Color.drivyInkMuted
        }
    }

    // MARK: - Standings

    /// The group as a ranked list, cut into lanes by the two movement zones:
    /// the promotion band and the demotion band each announce themselves with a
    /// dashed lane mark carrying their existing copy (S5).
    private var standingsSection: some View {
        Section {
            if model.ranking.isEmpty {
                Text("Tu grupo de esta semana aún no tiene posiciones. Aparecerán en cuanto haya XP.")
                    .font(.drivyBody)
                    .foregroundStyle(Color.drivyInkMuted)
                    .listRowBackground(Color.drivyPaper)
            }

            ForEach(LeagueStandingsLanes.items(for: model.ranking)) { item in
                switch item {
                case .divider(let zone):
                    LeagueLaneDivider(zone: zone)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.drivyPaper)

                case .row(let row):
                    LeagueStandingsRow(
                        position: row.place,
                        displayName: row.displayName,
                        xpText: row.xpText,
                        isMe: row.isMe,
                        zone: row.zone
                    )
                    .listRowBackground(Color.drivyPaper)
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyAlertText)
                    .listRowBackground(Color.drivyPaper)
            }
        } header: {
            Text(model.divisionTitle)
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(PublicLeagueZone.promotion.explanation)
                Text(PublicLeagueZone.demotion.explanation)
            }
            .font(.drivyFootnote)
            .foregroundStyle(Color.drivyInkMuted)
        }
    }
}

// MARK: - Standings rows

/// One position of a league standings list (S5): the rank in the condensed
/// headline, the visible name, and the XP of the week trailing.
///
/// The caller's own row is marked with a 3 pt tint bar on the leading edge —
/// a mark, not a filled row, so the list keeps one surface (S3). The mark is
/// announced once, so the position is not only a colour the eye has to catch.
///
/// A zone arrow, when the row sits in a movement band, is the same copy VoiceOver
/// already read for the band (`PublicLeagueZone.label`).
struct LeagueStandingsRow: View {

    /// 1-based position, printed with tabular figures so the column lines up.
    let position: Int

    let displayName: String

    /// Already formatted (`LeagueXPText`): the row shows what it is given.
    let xpText: String

    /// `true` on the caller's own row.
    var isMe: Bool = false

    /// `nil` outside both movement bands.
    var zone: PublicLeagueZone? = nil

    /// Copy of the own-row mark, announced with it.
    static let ownRowLabel = "Tú"

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.drivyHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
                .frame(minWidth: 28, alignment: .leading)

            Text(displayName)
                .font(.drivyBodyStrong)
                .foregroundStyle(Color.drivyInk)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if let zone {
                Image(systemName: zone.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(zone.tint)
                    .accessibilityLabel(zone.label)
            }

            Text(xpText)
                .font(.drivyHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
        }
        .overlay(alignment: .leading) {
            if isMe {
                Rectangle()
                    .fill(Color.drivyTint)
                    .frame(width: 3)
                    // In the row's leading inset, clear of the position digits.
                    .offset(x: -10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.ownRowLabel)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The dashed lane mark that opens a movement zone of the standings, with the
/// copy of the zone it announces (S5).
struct LeagueLaneDivider: View {

    let zone: PublicLeagueZone

    var body: some View {
        HStack(spacing: 10) {
            LeagueLaneDashLine()
                .fill(Color.drivyInkMuted)
                .frame(height: RoadMetrics.centreLineWidth)

            HStack(spacing: 5) {
                Image(systemName: zone.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(zone.tint)
                    .accessibilityHidden(true)

                Text(zone.label)
                    .font(.drivyKicker)
                    .foregroundStyle(Color.drivyInkMuted)
            }

            LeagueLaneDashLine()
                .fill(Color.drivyInkMuted)
                .frame(height: RoadMetrics.centreLineWidth)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal lane mark: the dash rhythm of the road, laid flat (S3).
///
/// Only whole dashes are drawn; a remainder at the edge would read as a smudge
/// instead of as a line.
struct LeagueLaneDashLine: Shape {

    /// Length of one dash, shared with the centre line of the road.
    var dashLength: CGFloat = RoadMetrics.dashLength

    /// Gap between two dashes.
    var gapLength: CGFloat = RoadMetrics.dashGap

    func path(in rect: CGRect) -> Path {
        let cycle = dashLength + gapLength
        guard cycle > 0, rect.height > 0, rect.width > 0 else { return Path() }

        let dash = min(dashLength, rect.width)
        var path = Path()
        var x = rect.minX

        while x + dash <= rect.maxX {
            path.addRect(CGRect(x: x, y: rect.minY, width: dash, height: rect.height))
            x += cycle
        }

        return path
    }
}

// MARK: - Zone lanes of the standings

/// What the standings list has to show, in order: a row, or the mark that opens
/// a movement zone.
///
/// The zone copy itself is not repeated on every row of the band: one divider
/// says where the band starts, and only the rows that move carry their arrow.
enum LeagueStandingsItem: Identifiable, Equatable {

    case divider(PublicLeagueZone)
    case row(PublicLeagueRankingRow)

    var id: String {
        switch self {
        case .divider(let zone):
            return "divider-\(zone.rawValue)"
        case .row(let row):
            return "row-\(row.id)"
        }
    }
}

/// The pure rule behind the standings list (S6: presentation only, no view
/// model and no scoring touched).
///
/// The server marks each row with its zone (`public_league_ranking()`, S2), so
/// the client does not recompute the bands; it only announces each band once,
/// where its first row appears.
enum LeagueStandingsLanes {

    /// `items(for:)`: the rows to render, with one divider inserted before the
    /// first row of every movement zone present in `rows`.
    ///
    /// Nothing is dropped and nothing is reordered: the list the server sent is
    /// the list the screen shows, plus at most one divider per zone.
    static func items(for rows: [PublicLeagueRankingRow]) -> [LeagueStandingsItem] {
        var items: [LeagueStandingsItem] = []
        var announced: [PublicLeagueZone] = []

        for row in rows {
            if let zone = row.zone, !announced.contains(zone) {
                announced.append(zone)
                items.append(.divider(zone))
            }
            items.append(.row(row))
        }

        return items
    }
}

extension PublicLeagueZone {

    /// Colour of the zone as text or as a glyph: promotion goes, demotion warns
    /// (S3). `signRed` is never used for text: `alertText` is the readable red
    /// of the current appearance.
    var tint: Color {
        switch self {
        case .promotion:
            return Color.drivyGo
        case .demotion:
            return Color.drivyAlertText
        }
    }
}

// MARK: - Previews

#Preview("Invitación") {
    List {
        PublicLeagueInvitationCard(model: PublicLeagueViewModel())
    }
    .background(Color.drivyPaper)
}

#Preview("Liga pública") {
    List {
        PublicLeaguePanel(model: PublicLeagueViewModel())
    }
    .background(Color.drivyPaper)
}
