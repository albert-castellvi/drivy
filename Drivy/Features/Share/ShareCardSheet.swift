import SwiftUI
import UIKit

/// Sheet with the rendered card plus the system share sheet (S8): the same sheet
/// is what puts the picture in an Instagram or TikTok story.
struct ShareCardSheet: View {

    let userID: String

    /// Plan in force: the freezes of the streak depend on it (S1/S8), and the card
    /// must print the same streak the Hoy tab prints.
    @EnvironmentObject private var freemium: FreemiumService

    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = ShareCardViewModel()
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.drivyPaper)
            .navigationTitle("Tu tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task(id: loadID) { await load() }
        }
    }

    /// Reloads when the user changes and when the plan arrives: before StoreKit
    /// answers, the card would count the free allowance.
    private var loadID: String {
        "\(userID)|\(freemium.plan?.rawValue ?? "unknown")"
    }

    @ViewBuilder
    private var content: some View {
        if let card = model.card {
            // The card is a printed object, so it needs no elevation: a hairline
            // rule is all the separation it wants (S3, S4: no shadows).
            ShareCardView(model: card)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.drivyRule, lineWidth: 1)
                )
                .accessibilityLabel(card.accessibilitySummary)

            if let image {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(
                        "Mi Driver Score en Drivy",
                        image: Image(uiImage: image)
                    )
                ) {
                    Label("Compartir en stories", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.directionSign)
            } else {
                ProgressView()
            }

            Text("Imagen cuadrada de 1080 × 1080, lista para Instagram o TikTok.")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
                .multilineTextAlignment(.center)
        } else if model.isLoading {
            ProgressView("Preparando tu tarjeta…")
                .font(.drivyBody)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyAlertText)
                .multilineTextAlignment(.center)
        } else {
            Text("Registra un trayecto para tener algo que compartir.")
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func load() async {
        guard !userID.isEmpty else { return }

        await model.load(userID: userID, plan: freemium.plan)
        guard let card = model.card else { return }

        // Rendering is explicit instead of implicit so the share sheet gets a
        // ready-made image and never has to draw the card again.
        image = ShareCardRenderer.image(for: card)
    }
}

#Preview {
    ShareCardSheet(userID: "")
        .environmentObject(FreemiumService(anchorDate: Date()))
}
