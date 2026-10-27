import SwiftUI
import UIKit

/// S8: square share card, generated on-device.
///
/// The card is laid out at `side` points and rendered at `scale`, so the resulting
/// image is 1080 × 1080 px (the size Instagram and TikTok stories want) without
/// keeping a huge view hierarchy alive.
struct ShareCardView: View {

    static let side: CGFloat = 360

    static let renderScale: CGFloat = 3

    let model: ShareCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text(DrivyConfig.appDisplayName)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .opacity(0.9)

            Spacer(minLength: 12)

            Text(model.scoreText)
                .font(.system(size: 104, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("Driver Score")
                .font(.subheadline.weight(.semibold))
                .opacity(0.8)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Label(model.streakText, systemImage: "flame.fill")
                Label(model.leagueText, systemImage: "trophy.fill")
            }
            .font(.subheadline.weight(.medium))

            Text(LeagueInviteLink.host)
                .font(.caption2)
                .opacity(0.8)
                .padding(.top, 12)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: Self.side, height: Self.side, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
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
    ShareCardView(
        model: ShareCardModel(
            score: 87,
            streakDays: 3,
            leaguePosition: 2,
            leagueName: "Los del barrio",
            leagueSize: 4
        )
    )
    .padding()
}
