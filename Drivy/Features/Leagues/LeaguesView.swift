import SwiftUI

/// Tab "Ligas": private friend leagues with a weekly ranking (filled in by T4).
struct LeaguesView: View {

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PlaceholderCard(
                        systemImage: "trophy.fill",
                        title: "Tu liga",
                        message: "Compite con hasta 25 amigos por el mejor Driver Score de la semana."
                    )

                    PlaceholderCard(
                        systemImage: "person.3.fill",
                        title: "Invitar amigos",
                        message: "En breve podrás compartir un enlace para que se unan a tu liga."
                    )
                }
                .padding()
            }
            .navigationTitle("Ligas")
        }
    }
}

#Preview {
    LeaguesView()
}
