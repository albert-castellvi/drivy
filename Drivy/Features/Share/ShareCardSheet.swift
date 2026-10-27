import SwiftUI
import UIKit

/// Sheet with the rendered card plus the system share sheet (S8): the same sheet
/// is what puts the picture in an Instagram or TikTok story.
struct ShareCardSheet: View {

    let userID: String

    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = ShareCardViewModel()
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                content
            }
            .padding()
            .navigationTitle("Tu tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task(id: userID) { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let card = model.card {
            ShareCardView(model: card)
                .shadow(radius: 12, y: 6)
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
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
            }

            Text("Imagen cuadrada de 1080 × 1080, lista para Instagram o TikTok.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if model.isLoading {
            ProgressView("Preparando tu tarjeta…")
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else {
            Text("Registra un trayecto para tener algo que compartir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func load() async {
        guard !userID.isEmpty else { return }

        await model.load(userID: userID)
        guard let card = model.card else { return }

        // Rendering is explicit instead of implicit so the share sheet gets a
        // ready-made image and never has to draw the card again.
        image = ShareCardRenderer.image(for: card)
    }
}

#Preview {
    ShareCardSheet(userID: "")
}
