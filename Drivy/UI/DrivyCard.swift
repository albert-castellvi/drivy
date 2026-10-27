import SwiftUI

extension View {

    /// Card look shared by the MVP screens: same shape and padding as
    /// `PlaceholderCard`, so the placeholders and the real content line up.
    func drivyCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
            )
    }
}

/// Small labelled figure used by the detail screens (driver score, km, time…).
struct DriveMetric: View {

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack {
            DriveMetric(title: "Distancia", value: "12.3 km")
            DriveMetric(title: "Nota", value: "87")
        }
    }
    .drivyCard()
    .padding()
}
