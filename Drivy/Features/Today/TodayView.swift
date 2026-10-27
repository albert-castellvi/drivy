import SwiftUI

/// Tab "Hoy": daily Driver Score and streak live here (filled in by T4).
struct TodayView: View {

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PlaceholderCard(
                        systemImage: "speedometer",
                        title: "Driver Score",
                        message: "Tu nota de hoy aparecerá aquí en cuanto registres tu primer trayecto."
                    )

                    PlaceholderCard(
                        systemImage: "flame.fill",
                        title: "Racha",
                        message: "Conduce cada día para mantener la racha. Tienes un día de margen antes de perderla."
                    )

                    PlaceholderCard(
                        systemImage: "car.fill",
                        title: "Trayectos",
                        message: "El registro automático de trayectos llega en la siguiente entrega."
                    )
                }
                .padding()
            }
            .navigationTitle("Hoy")
        }
    }
}

#Preview {
    TodayView()
}
