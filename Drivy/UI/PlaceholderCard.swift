import SwiftUI

/// Reusable placeholder used by the MVP screens that T4 fills with real data.
struct PlaceholderCard: View {

    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary)
        )
    }
}

#Preview {
    PlaceholderCard(
        systemImage: "speedometer",
        title: "Título",
        message: "Texto de ejemplo para la tarjeta."
    )
    .padding()
}
