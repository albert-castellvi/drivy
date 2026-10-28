import SwiftUI
import UIKit

/// S8: square share card, generated on-device.
///
/// The card is laid out at `side` points and rendered at `scale`, so the resulting
/// image is 1080 × 1080 px (the size Instagram and TikTok stories want) without
/// keeping a huge view hierarchy alive.
///
/// It is a printed object, not a screen (S6): it always renders the light palette,
/// whatever the system mode is, with no materials and no blur, because
/// `ImageRenderer` cannot resolve either. The road vocabulary it prints is the one
/// of S3 — the day's score as a hitto standing on a strip of asphalt, the facts of
/// the day as Spanish road signs, the wordmark in Barlow Condensed.
struct ShareCardView: View {

    static let side: CGFloat = 360

    static let renderScale: CGFloat = 3

    let model: ShareCardModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoadSurface(isMoving: false)
                .frame(width: RoadMetrics.roadWidth)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.trailing, 20)
                .padding(.vertical, 22)
        }
        .frame(width: Self.side, height: Self.side, alignment: .topLeading)
        .background(ShareCardPalette.paper)
        // S6: the card ignores the system appearance. Two belts: the environment
        // value is forced to light for everything inside, and every colour this
        // view draws itself is the fixed light value of its token, so no dynamic
        // resolution has to be trusted for the printed image to be right.
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DrivyConfig.appDisplayName)
                .font(.drivyTitle)
                .foregroundStyle(ShareCardPalette.primary)

            Spacer(minLength: 12)

            HStack(alignment: .bottom, spacing: 12) {
                // The screen post of `KmPostSize.score` is 74 × 92 and reads as a
                // header mark; on a 360 pt print the number is the object, so the
                // same hitto is drawn larger. Its face and ink come from the sign
                // tokens, which are fixed in both modes: nothing here depends on the
                // trait environment.
                KmPost(
                    value: model.scoreText,
                    capColor: Color.drivySignRed,
                    isToday: true,
                    size: ShareCardLayout.postSize
                )

                Text("Driver Score")
                    .font(.drivyHeadline)
                    .foregroundStyle(ShareCardPalette.primary)
            }

            Spacer(minLength: 14)

            signals

            if let quietLine = ShareCardSignals.quietLine(for: model) {
                Text(quietLine)
                    .font(.drivyKicker)
                    .foregroundStyle(ShareCardPalette.secondary)
                    .padding(.top, 8)
            }

            Spacer(minLength: 12)

            Text(LeagueInviteLink.host)
                .font(.drivyKicker)
                .foregroundStyle(ShareCardPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The facts of the day, each wearing a road sign instead of a gamified icon.
    @ViewBuilder
    private var signals: some View {
        let cardSignals = ShareCardSignals.signals(for: model)

        if !cardSignals.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                ForEach(cardSignals) { signal in
                    VStack(spacing: 5) {
                        RoadSign(kind: signal.kind, size: ShareCardLayout.signSize)

                        Text(signal.caption)
                            .font(.drivyKicker)
                            .foregroundStyle(ShareCardPalette.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// The fixed light palette of the printed card (S6): the light value of the S3
/// tokens, read without a trait environment, so no system mode can move it.
enum ShareCardPalette {

    static var paper: Color { Color(uiColor: DrivyToken.paper.light) }

    static var primary: Color { Color(uiColor: DrivyToken.ink.light) }

    static var secondary: Color { Color(uiColor: DrivyToken.inkMuted.light) }
}

/// Layout sizes of the card. They belong to a printed 360 pt square, not to the
/// screen metrics, so they live here instead of in `RoadMetrics` (S3).
enum ShareCardLayout {

    static var postSize: CGSize { CGSize(width: 100, height: 126) }

    static var signSize: CGFloat { 30 }
}

// MARK: - What the card is allowed to say

/// One fact of the day, printed as a road sign with its caption.
struct ShareCardSignal: Equatable, Identifiable {

    let kind: RoadSign.Kind

    let caption: String

    var id: String { "\(kind)-\(caption)" }
}

/// The signals the card can honestly print.
///
/// `ShareCardModel` carries the score, the streak, the public division and the
/// weekly position — and no event counts. So the row prints exactly those facts,
/// each with the copy the model already produces, and never claims a hazard the
/// card has no data about (S6: honest copy, nothing that invites to drive more).
/// An absence is never dressed up as an achievement: it gets no sign, at most the
/// quiet line of `quietLine`.
enum ShareCardSignals {

    /// At most three signs, in the order the card has always read them: the streak,
    /// the public division, the weekly position.
    static func signals(for model: ShareCardModel) -> [ShareCardSignal] {
        var result: [ShareCardSignal] = []

        if model.streakDays > 0 {
            result.append(
                ShareCardSignal(kind: .info(systemName: "checkmark"), caption: model.streakText)
            )
        }

        if let divisionText = model.divisionText {
            result.append(
                ShareCardSignal(kind: .info(systemName: "flag"), caption: divisionText)
            )
        }

        if model.leaguePosition != nil {
            result.append(
                ShareCardSignal(kind: .info(systemName: "person.3.fill"), caption: model.leagueText)
            )
        }

        return result
    }

    /// A fact that is not an achievement is still a fact, so it keeps its line on
    /// the card — without a sign and in the quiet colour — exactly where the screen
    /// has always printed it (`showsLeagueLine`). This is what keeps the picture
    /// and `accessibilitySummary` telling the same story.
    static func quietLine(for model: ShareCardModel) -> String? {
        guard model.showsLeagueLine, model.leaguePosition == nil else { return nil }
        return model.leagueText
    }
}

/// `ImageRenderer` is main-actor bound, so the rasterization lives here instead of
/// inside the view.
@MainActor
enum ShareCardRenderer {

    static func image(
        for model: ShareCardModel,
        scale: CGFloat = ShareCardView.renderScale
    ) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(model: model))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

#Preview {
    VStack(spacing: 16) {
        ShareCardView(
            model: ShareCardModel(
                score: 87,
                streakDays: 3,
                leaguePosition: 2,
                leagueName: "Los del barrio",
                leagueSize: 4,
                divisionName: "Plata"
            )
        )

        ShareCardView(
            model: ShareCardModel(
                score: 87,
                streakDays: 3,
                leaguePosition: nil,
                leagueName: nil,
                leagueSize: 0
            )
        )
    }
    .padding()
}
